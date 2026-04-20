# Manual Deployment: GKE Inference Gateway

This guide walks you through deploying the GKE Inference Gateway step by step. The GKE Inference Gateway uses the Kubernetes Gateway API with GKE-native InferencePool resources and an Endpoint Picker (EPP) to route OpenAI-compatible inference requests to vLLM model servers running on GKE.

## Overview

The deployment pipeline has three phases:

- **Phase A:** Configure Terraform variables from the provided template.
- **Phase B:** Enable Google Cloud APIs and apply Terraform to provision infrastructure.
- **Phase C:** Deploy Kubernetes resources (CRDs, custom-metrics adapter, Gateway, model workloads, and optional features).

By the end of this guide, you will have a working internal HTTPS gateway that routes inference requests to one or more models running on GKE GPU nodes.

---

## Prerequisites

### Tools

Install the following tools before you begin:

| Tool | Purpose |
| --- | --- |
| `gcloud` | Google Cloud CLI |
| `terraform` | Infrastructure as Code |
| `kubectl` | Kubernetes cluster management |
| `helm` | Kubernetes package manager (required for semantic cache feature) |
| `kustomize` | Kubernetes manifest composition (bundled with `kubectl`) |
| `envsubst` | Environment variable substitution in templates |

### Google Cloud resources

- A Google Cloud project with billing enabled.
- An existing Cloud DNS managed zone for your domain. See [DNS Setup](dns-setup.md) for instructions.
- Sufficient GPU quota in your target region (for example, `NVIDIA_L4_GPUS` or `NVIDIA_H100_GPUS`).
- IAM permissions to create GKE clusters, VPCs, DNS records, and related resources.

### Optional

- A [Hugging Face API token](https://huggingface.co/settings/tokens) if you need to access gated models.

---

## Phase A: Configure Terraform variables

In this phase, you render the Terraform variable file from the provided template.

### Step 1: Set environment variables

Export the variables that `envsubst` uses to populate the template:

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export REGION="YOUR_REGION"                  # e.g., us-east4
export DNS_ZONE_NAME="YOUR_DNS_ZONE_NAME"    # Cloud DNS managed zone name
export HF_TOKEN=""                           # Hugging Face token (leave empty to skip)
```

Resolve the domain name from your DNS zone:

```bash
export DOMAIN_NAME=$(gcloud dns managed-zones describe "$DNS_ZONE_NAME" \
    --project "$PROJECT_ID" \
    --format="value(dnsName)" | sed 's/\.$//')
```

Set feature flags and model list:

```bash
# Models to deploy (comma-separated)
MODELS="gemma-3-27b-it"

# Features: custom-metrics, semantic-cache, unified-extension, model-armor
FEATURES="custom-metrics"

# Hugging Face token handling
export ENABLE_HF="false"
if [ -n "$HF_TOKEN" ]; then
    export HUGGINGFACE_TOKEN="\"$HF_TOKEN\""
    export ENABLE_HF="true"
else
    export HUGGINGFACE_TOKEN="null"
fi

# Feature flags for Terraform
export ENABLE_MODEL_ARMOR="false"
export ENABLE_SEMANTIC_CACHE="false"
if [[ $FEATURES == *"model-armor"* ]] || [[ $FEATURES == *"unified-extension"* ]]; then
    ENABLE_MODEL_ARMOR="true"
fi
if [[ $FEATURES == *"semantic-cache"* ]] || [[ $FEATURES == *"unified-extension"* ]]; then
    ENABLE_SEMANTIC_CACHE="true"
fi

# Convert models list to Terraform list format
MODEL_NAMESPACES_TF="["
IFS=',' read -ra MODEL_ARRAY <<< "$MODELS"
for i in "${!MODEL_ARRAY[@]}"; do
    MODEL_NAMESPACES_TF+="\"${MODEL_ARRAY[$i]}\""
    if [ "$i" -lt $((${#MODEL_ARRAY[@]} - 1)) ]; then
        MODEL_NAMESPACES_TF+=", "
    fi
done
MODEL_NAMESPACES_TF+="]"
export MODEL_NAMESPACES_TF

# VPC name (default used by the module)
export VPC_NAME="inference-vpc"
```

### Step 2: Render the tfvars file

Run `envsubst` with a restricted variable list to avoid clobbering HCL `${}` interpolation syntax:

```bash
cd terraform/

envsubst '$PROJECT_ID $REGION $DOMAIN_NAME $DNS_ZONE_NAME $HUGGINGFACE_TOKEN $ENABLE_HF $ENABLE_MODEL_ARMOR $ENABLE_SEMANTIC_CACHE $MODEL_NAMESPACES_TF $VPC_NAME' \
    < gke-gateway.tfvars.tmpl \
    > gke-gateway.tfvars
```

> **Important:** You must use the restricted variable list shown above. Running `envsubst` without this list replaces all `${}` expressions in the file, which breaks HCL interpolation syntax like `${REGION}` inside Terraform resource blocks.

### Step 3: Review the generated file

Open `terraform/gke-gateway.tfvars` and verify that all values are populated correctly. The file should contain no unresolved `${VARIABLE}` placeholders. You can check programmatically:

```bash
grep -P '\$\{[A-Z_]+\}' gke-gateway.tfvars && echo "ERROR: Unresolved placeholders found" || echo "OK: No unresolved placeholders"
```

### Reference: tfvars structure

The generated `gke-gateway.tfvars` contains these key sections:

| Section | Description |
| --- | --- |
| `project_id`, `region` | Core project and region identifiers |
| `dns_zone_domain`, `dns_zone_name` | DNS zone for certificate and record creation |
| `clusters` | GKE cluster configuration (name, DNS domain, deletion protection) |
| `enable_model_armor`, `enable_semantic_cache` | Feature flags for security features |
| `apigee_*` | Apigee organization, environments, instances, and DNS zone peering |
| `gke_gateway` | Gateway API configuration (name, namespace, hostname, class) |
| `self_managed_gateway` | Set to `null` for GKE Gateway mode |
| `huggingface_token`, `model_namespaces` | Model access and deployment configuration |

---

## Phase B: Deploy infrastructure with Terraform

### Step 1: Enable required Google Cloud APIs

```bash
gcloud services enable \
    compute.googleapis.com \
    container.googleapis.com \
    aiplatform.googleapis.com \
    dns.googleapis.com \
    certificatemanager.googleapis.com \
    modelarmor.googleapis.com \
    apigee.googleapis.com \
    secretmanager.googleapis.com \
    iap.googleapis.com \
    artifactregistry.googleapis.com \
    run.googleapis.com \
    serviceusage.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --project "$PROJECT_ID"
```

### Step 2: Initialize and apply Terraform

```bash
cd terraform/

terraform init
terraform apply -var-file="gke-gateway.tfvars" -auto-approve
```

> **Note:** Remove `-auto-approve` if you prefer to review the plan before applying.

### Step 3: Capture Terraform outputs

After a successful apply, capture the outputs needed for Phase C:

```bash
# Apigee environment name
export APIGEE_ENV=$(terraform output -json apigee_environments 2>/dev/null \
    | grep -o '"[^"]*":' | head -1 | tr -d '":')
APIGEE_ENV=${APIGEE_ENV:-"apis-prod"}

# Model Armor template path
export MODEL_ARMOR_TEMPLATE=$(terraform output -raw model_armor_template_name 2>/dev/null || true)
MODEL_ARMOR_TEMPLATE=${MODEL_ARMOR_TEMPLATE:-"projects/${PROJECT_ID}/locations/${REGION}/templates/default-safety-template"}

# Static IP name for the Gateway
export STATIC_IP_NAME=$(terraform output -raw internal_gateway_ip_name 2>/dev/null || echo "igw-internal-gateway-ip")

# VPC and subnet names
export VPC_NAME=$(terraform output -raw vpc_name 2>/dev/null || echo "inference-vpc")
export SUBNET_NAME=$(terraform output -raw subnet_name 2>/dev/null || echo "gke-subnet-us-central1")
```

Verify the captured values:

```bash
echo "APIGEE_ENV:           $APIGEE_ENV"
echo "MODEL_ARMOR_TEMPLATE: $MODEL_ARMOR_TEMPLATE"
echo "STATIC_IP_NAME:       $STATIC_IP_NAME"
echo "VPC_NAME:             $VPC_NAME"
echo "SUBNET_NAME:          $SUBNET_NAME"
```

---

## Phase C: Deploy Kubernetes resources

### Step 1: Get GKE credentials

```bash
gcloud container clusters get-credentials "inference-cluster" \
    --region "$REGION" \
    --project "$PROJECT_ID"
```

### Step 2: Set Kubernetes deployment variables

```bash
cd k8s/

export GATEWAY_HOST="gateway.internal.$DOMAIN_NAME"
export SEMANTIC_PROXY_NAME="apigee-cache-backend"

# Build the RESOURCES_BLOCK for model directories
RESOURCES_BLOCK=""
IFS=',' read -ra MODEL_ARRAY <<< "$MODELS"
for m in "${MODEL_ARRAY[@]}"; do
    RESOURCES_BLOCK+="  - models/$m"$'\n'
done
export RESOURCES_BLOCK

# Build the COMPONENTS_BLOCK for enabled features
COMPONENTS_BLOCK=""
HAS_COMPONENTS=false
IFS=',' read -ra FEATURE_ARRAY <<< "$FEATURES"
for f in "${FEATURE_ARRAY[@]}"; do
    if [ -d "features/$f" ]; then
        if [ "$HAS_COMPONENTS" = false ]; then
            COMPONENTS_BLOCK+=$'\n'"components:"$'\n'
            HAS_COMPONENTS=true
        fi
        COMPONENTS_BLOCK+="  - features/$f"$'\n'
    fi
done
export COMPONENTS_BLOCK
```

### Step 3: Render feature templates (if applicable)

If you enabled `model-armor` or `unified-extension`, render their YAML templates:

```bash
FEATURE_ENVSUBST_VARS='$REGION $PROJECT_ID $MODEL_ARMOR_TEMPLATE $SEMANTIC_PROXY_NAME'

# Model Armor
if [ -f "features/model-armor/model-armor.yaml.tmpl" ]; then
    envsubst "$FEATURE_ENVSUBST_VARS" \
        < features/model-armor/model-armor.yaml.tmpl \
        > features/model-armor/model-armor.yaml
fi

# Unified Extension
if [ -f "features/unified-extension/unified-extension.yaml.tmpl" ]; then
    envsubst "$FEATURE_ENVSUBST_VARS" \
        < features/unified-extension/unified-extension.yaml.tmpl \
        > features/unified-extension/unified-extension.yaml
fi
```

### Step 4: Render Helm values (semantic cache only)

If you enabled `semantic-cache` or `unified-extension`, render the Apigee APIM operator values template. The Helm charts are pulled from the OCI registry automatically by Kustomize's `helmCharts` feature at build time.

```bash
FEATURE_ENVSUBST_VARS='$REGION $PROJECT_ID $MODEL_ARMOR_TEMPLATE $SEMANTIC_PROXY_NAME'

envsubst "$FEATURE_ENVSUBST_VARS" \
    < features/semantic-cache-infra/values.yaml.tmpl \
    > features/semantic-cache-infra/values.yaml
```

### Step 5: Render the root kustomization.yaml

```bash
KUST_ENVSUBST_VARS='$RESOURCES_BLOCK $COMPONENTS_BLOCK $GATEWAY_HOST $PROJECT_ID $REGION $STATIC_IP_NAME $APIGEE_ENV $MODEL_ARMOR_TEMPLATE $SEMANTIC_PROXY_NAME $VPC_NAME $SUBNET_NAME'

envsubst "$KUST_ENVSUBST_VARS" \
    < kustomization-gke.yaml.tmpl \
    > kustomization.yaml
```

### Step 6: Deploy CRDs

If semantic cache or unified extension is enabled, use `kubectl kustomize --enable-helm` to render the Helm charts (including Apigee CRDs) and apply them first:

```bash
# With semantic cache or unified extension:
kubectl kustomize --enable-helm . | kubectl apply --server-side -f - 2>/dev/null || true
kubectl apply -k crds/
sleep 20

# Without semantic cache:
# kubectl apply -k crds/
# sleep 20
```

### Step 7: Deploy custom-metrics adapter

```bash
kubectl apply -k custom-metrics/
```

### Step 8: Deploy all resources

```bash
kubectl kustomize --enable-helm . | kubectl apply -f -
```

### Step 9: Wait for Apigee operator (semantic cache only)

If you enabled semantic cache or unified extension, wait for the operator and deploy the semantic cache proxy:

```bash
# Wait for the operator deployment
kubectl wait --for=condition=Available deployment/apigee-apim-operator \
    -n apim --timeout=300s

# Wait for the ApigeeBackendService to reach CREATED state
for i in $(seq 1 60); do
    STATE=$(kubectl get apigeebackendservice apigee-cache-backend \
        -o jsonpath='{.status.currentState}' 2>/dev/null || echo "Unknown")
    if [ "$STATE" == "CREATED" ]; then
        echo "ApigeeBackendService is established (state: $STATE)"
        sleep 30
        break
    fi
    echo "Waiting for ApigeeBackendService... (attempt $i/60, state: $STATE)"
    sleep 10
done
```

### Step 10: Deploy semantic cache proxy to Apigee (semantic cache only)

This step builds and uploads the Apigee proxy bundle, then deploys it to your Apigee environment.

```bash
# Capture additional Terraform outputs
cd ../terraform/
PROJECT_NUMBER=$(terraform output -raw foundation_project_number)
VERTEX_ENDPOINT_DOMAIN=$(terraform output -raw vertex_ai_index_endpoint_domain)
VERTEX_ENDPOINT_ID=$(terraform output -raw vertex_ai_endpoint_numeric_id)
VERTEX_INDEX_ID=$(terraform output -raw vertex_ai_index_numeric_id)
VERTEX_DEPLOYED_INDEX_ID=$(terraform output -raw vertex_ai_deployed_index_id)

PROXY_BUNDLE_NAME="apigee-cache-backend"
PROXY_SA="apigee-proxy-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
SIMILARITY_THRESHOLD="0.95"
TTL_SECONDS="600"
EMBEDDING_MODEL="gemini-embedding-001"
POLICY_SRC="modules/apigee-semantic-proxy"

# Stage the proxy bundle
STAGING="/tmp/proxy-bundle-$$"
mkdir -p "$STAGING/apiproxy/policies" "$STAGING/apiproxy/proxies"

cp "$POLICY_SRC/bundle-extension/apiproxy/proxies/default.xml" "$STAGING/apiproxy/proxies/"
cp "$POLICY_SRC/bundle-extension/apiproxy/policies/AM-Set-Cache-Headers.xml" "$STAGING/apiproxy/policies/"
cp "$POLICY_SRC/bundle-extension/apiproxy/policies/EV-Extract-Body-Debug.xml" "$STAGING/apiproxy/policies/"
cp "$POLICY_SRC/bundle-extension/apiproxy/policies/RF-Return-Cached-Response.xml" "$STAGING/apiproxy/policies/"

# Create the proxy descriptor XML
cat > "$STAGING/apiproxy/$PROXY_BUNDLE_NAME.xml" <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="apigee-cache-backend">
  <DisplayName>apigee-cache-backend</DisplayName>
  <Description>Semantic caching proxy</Description>
  <BasePaths>/</BasePaths>
  <Policies>
    <Policy>SCL-Semantic-Cache-Lookup</Policy>
    <Policy>SCP-Semantic-Cache-Populate</Policy>
    <Policy>RF-Return-Cached-Response</Policy>
    <Policy>AM-Set-Cache-Headers</Policy>
  </Policies>
  <ProxyEndpoints>
    <ProxyEndpoint>default</ProxyEndpoint>
  </ProxyEndpoints>
  <TargetEndpoints/>
</APIProxy>
XMLEOF

# Render the Semantic Cache Lookup policy
sed -e "s/\${region}/$REGION/g" \
    -e "s/\${project_number}/$PROJECT_NUMBER/g" \
    -e "s/\${embedding_model}/$EMBEDDING_MODEL/g" \
    -e "s/\${public_endpoint_domain}/$VERTEX_ENDPOINT_DOMAIN/g" \
    -e "s/\${endpoint_numeric_id}/$VERTEX_ENDPOINT_ID/g" \
    -e "s/\${deployed_index_id}/$VERTEX_DEPLOYED_INDEX_ID/g" \
    -e "s/\${similarity_threshold}/$SIMILARITY_THRESHOLD/g" \
    "$POLICY_SRC/templates/policies/SCL-Semantic-Cache-Lookup.xml.tftpl" \
    > "$STAGING/apiproxy/policies/SCL-Semantic-Cache-Lookup.xml"

# Render the Semantic Cache Populate policy
sed -e "s/\${region}/$REGION/g" \
    -e "s/\${project_number}/$PROJECT_NUMBER/g" \
    -e "s/\${index_numeric_id}/$VERTEX_INDEX_ID/g" \
    -e "s/\${ttl_seconds}/$TTL_SECONDS/g" \
    "$POLICY_SRC/templates/policies/SCP-Semantic-Cache-Populate.xml.tftpl" \
    > "$STAGING/apiproxy/policies/SCP-Semantic-Cache-Populate.xml"

# Zip and upload
cd "$STAGING"
zip -r /tmp/proxy-bundle.zip apiproxy/

TOKEN=$(gcloud auth print-access-token)

UPLOAD_RESPONSE=$(curl -s -X POST \
    "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apis?name=${PROXY_BUNDLE_NAME}&action=import" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: multipart/form-data" \
    -F "file=@/tmp/proxy-bundle.zip")

REVISION=$(echo "$UPLOAD_RESPONSE" | grep -o '"revision": *"[^"]*"' | cut -d'"' -f4)
echo "Uploaded proxy revision: $REVISION"

# Deploy the revision
curl -s -X POST \
    "https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${APIGEE_ENV}/apis/${PROXY_BUNDLE_NAME}/revisions/${REVISION}/deployments?override=true" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"serviceAccount\": \"${PROXY_SA}\"}"

echo "Semantic cache proxy deployed."
```

---

## Validation

### Check pod status

```bash
kubectl get pods --all-namespaces -l app.kubernetes.io/part-of=inference-gateway
```

### Check the Gateway resource

```bash
kubectl get gateway -n inference-gateway
kubectl describe gateway unified-inference-gateway -n inference-gateway
```

### Check HTTPRoutes

```bash
kubectl get httproutes --all-namespaces
```

### Send a test request

The gateway is an internal HTTPS endpoint. Run a test from within the VPC (for example, from a GCE instance or a pod inside the cluster):

```bash
curl -k -X POST "https://gateway.internal.YOUR_DOMAIN/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "gemma-3-27b-it",
        "messages": [{"role": "user", "content": "Hello"}]
    }'
```

> **Note:** The load balancer may need a few minutes to provision and pass health checks before requests succeed.

---

## Adding a new model

To add a new model to your GKE Inference Gateway, create a model overlay directory and update the kustomization template.

### Step 1: Create the model directory

```bash
mkdir -p k8s/models/YOUR_MODEL_NAME
```

### Step 2: Create namespace.yaml

```yaml
# k8s/models/YOUR_MODEL_NAME/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: YOUR_MODEL_NAME
  labels:
    app.kubernetes.io/name: YOUR_MODEL_NAME
    app.kubernetes.io/part-of: inference-gateway
```

### Step 3: Create route.yaml

```yaml
# k8s/models/YOUR_MODEL_NAME/route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: YOUR_MODEL_NAME-route
spec:
  parentRefs:
    - name: unified-inference-gateway
      namespace: inference-gateway
      sectionName: https
  hostnames:
    - "gateway.internal.YOUR_DOMAIN"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /models/YOUR_MODEL_PREFIX/
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /
      backendRefs:
        - name: YOUR_MODEL_NAME-pool
          group: inference.networking.k8s.io
          kind: InferencePool
```

### Step 4: Create kustomization.yaml

Use the existing `gemma-3-27b-it` overlay as a reference. The key fields to customize are:

```yaml
# k8s/models/YOUR_MODEL_NAME/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - ../base
  - route.yaml

namespace: YOUR_MODEL_NAME
namePrefix: YOUR_MODEL_NAME-

configMapGenerator:
  - name: model-config
    behavior: replace
    literals:
      - MODEL_NAME=YOUR_MODEL_NAME
      - MODEL_ID=YOUR_ORG/YOUR_MODEL_ID        # e.g., google/gemma-3-27b-it
      - COMPUTE_CLASS=dws-flex-h100             # Match your GPU node pool
      - NEG_NAME=YOUR_MODEL_NAME-neg
      - POOL_NAME=YOUR_MODEL_NAME-pool
      - MODEL_NAMESPACE=YOUR_MODEL_NAME
      - PROJECT_ID=PLACEHOLDER_PROJECT_ID
    options:
      disableNameSuffixHash: true

replacements:
  - source:
      kind: ConfigMap
      name: model-config
      fieldPath: data.MODEL_NAME
    targets:
      - select:
          kind: Deployment
          name: vllm-deployment
        fieldPaths:
          - spec.template.metadata.labels.[ai.gke.io/model]
          - spec.selector.matchLabels.app
          - spec.template.metadata.labels.app
      - select:
          kind: Service
          name: llm-service
        fieldPaths:
          - spec.selector.app
      - select:
          kind: InferencePool
          name: pool
        fieldPaths:
          - spec.selector.matchLabels.app

  - source:
      kind: ConfigMap
      name: model-config
      fieldPath: data.MODEL_ID
    targets:
      - select:
          kind: Deployment
          name: vllm-deployment
        fieldPaths:
          - spec.template.spec.containers.[name=inference-server].env.[name=MODEL_ID].value

  - source:
      kind: ConfigMap
      name: model-config
      fieldPath: data.COMPUTE_CLASS
    targets:
      - select:
          kind: Deployment
          name: vllm-deployment
        fieldPaths:
          - spec.template.spec.nodeSelector.[cloud.google.com/compute-class]

  - source:
      kind: ConfigMap
      name: model-config
      fieldPath: data.POOL_NAME
    targets:
      - select:
          kind: Deployment
          labelSelector: app.kubernetes.io/name=epp
        fieldPaths:
          - spec.template.spec.containers.[name=epp].args.1

  - source:
      kind: ConfigMap
      name: model-config
      fieldPath: data.MODEL_NAMESPACE
    targets:
      - select:
          kind: Deployment
          labelSelector: app.kubernetes.io/name=epp
        fieldPaths:
          - spec.template.spec.containers.[name=epp].args.3
```

### Step 5: Add the model to the kustomization template

Add the new model to the `MODELS` variable and re-render the kustomization:

```bash
export MODELS="gemma-3-27b-it,YOUR_MODEL_NAME"
```

Then re-run Phase C starting from [Step 2](#step-2-set-kubernetes-deployment-variables) to rebuild the `RESOURCES_BLOCK` and re-render and apply the kustomization.

Also add the model namespace to your `gke-gateway.tfvars`:

```hcl
model_namespaces = ["gemma-3-27b-it", "YOUR_MODEL_NAME"]
```

And re-apply Terraform to provision any required namespace-level resources:

```bash
cd terraform/
terraform apply -var-file="gke-gateway.tfvars"
```
