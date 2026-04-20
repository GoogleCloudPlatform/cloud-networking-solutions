# Manual Deployment: Self-Managed Inference Gateway

This guide walks you through deploying the Self-Managed (DIY) Inference Gateway step by step. The Self-Managed Gateway uses a Regional Internal Application Load Balancer with a Body-Based Router (BBR) `ext_proc` service to route OpenAI-compatible inference requests based on the `model` field in the request body.

## Overview

The deployment pipeline has three phases:

- **Phase A:** Configure Terraform variables from the provided template.
- **Phase B:** Enable Google Cloud APIs, build and push the BBR Docker image, and apply Terraform to provision infrastructure.
- **Phase C:** Deploy Kubernetes model workloads and wait for GKE NEG endpoints to populate.

Unlike the GKE Inference Gateway, this mode does not use the Kubernetes Gateway API. Instead, Terraform creates the full load balancer stack (forwarding rule, URL map, backend services, health checks) and pre-creates zonal GKE NEGs that the GKE NEG controller adopts automatically.

---

## Prerequisites

### Tools

Install the following tools before you begin:

| Tool | Purpose |
| --- | --- |
| `gcloud` | Google Cloud CLI |
| `terraform` | Infrastructure as Code |
| `kubectl` | Kubernetes cluster management |
| `kustomize` | Kubernetes manifest composition (bundled with `kubectl`) |
| `envsubst` | Environment variable substitution in templates |
| `docker` | Build and push the BBR ext\_proc container image |

### Google Cloud resources

- A Google Cloud project with billing enabled.
- An existing Cloud DNS managed zone for your domain. See [DNS Setup](dns-setup.md) for instructions.
- Sufficient GPU quota in your target region (for example, `NVIDIA_L4_GPUS` or `NVIDIA_H100_GPUS`).
- IAM permissions to create GKE clusters, VPCs, load balancers, Artifact Registry repositories, DNS records, and related resources.

### Optional

- A [Hugging Face API token](https://huggingface.co/settings/tokens) if you need to access gated models.

---

## Phase A: Configure Terraform variables

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

# Hugging Face token handling
export ENABLE_HF="false"
if [ -n "$HF_TOKEN" ]; then
    export HUGGINGFACE_TOKEN="\"$HF_TOKEN\""
    export ENABLE_HF="true"
else
    export HUGGINGFACE_TOKEN="null"
fi

# Feature flags
export ENABLE_MODEL_ARMOR="false"
# Set to "true" if you want Model Armor protection
# export ENABLE_MODEL_ARMOR="true"

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
```

### Step 2: Render the tfvars file

Run `envsubst` with a restricted variable list to avoid clobbering HCL `${}` interpolation syntax:

```bash
cd terraform/

envsubst '$PROJECT_ID $REGION $DOMAIN_NAME $DNS_ZONE_NAME $HUGGINGFACE_TOKEN $ENABLE_HF $ENABLE_MODEL_ARMOR $MODEL_NAMESPACES_TF' \
    < diy-gateway.tfvars.tmpl \
    > diy-gateway.tfvars
```

> **Important:** You must use the restricted variable list shown above. Running `envsubst` without this list replaces all `${}` expressions in the file, which breaks HCL interpolation syntax inside Terraform resource blocks.

### Step 3: Review the generated file

Open `terraform/diy-gateway.tfvars` and verify that all values are populated correctly:

```bash
grep -P '\$\{[A-Z_]+\}' diy-gateway.tfvars && echo "ERROR: Unresolved placeholders found" || echo "OK: No unresolved placeholders"
```

### Reference: tfvars structure

The generated `diy-gateway.tfvars` contains these key sections:

| Section | Description |
| --- | --- |
| `project_id`, `region` | Core project and region identifiers |
| `dns_zone_domain`, `dns_zone_name` | DNS zone for certificate and record creation |
| `clusters` | GKE cluster configuration |
| `enable_model_armor` | Feature flag for Model Armor security |
| `self_managed_gateway` | Full gateway configuration object (see below) |
| `gke_gateway` | Set to `null` for DIY mode |

The `self_managed_gateway` object controls:

- **`domain`**: Gateway hostname and HTTPS settings
- **`load_balancer`**: Static IP configuration
- **`backends`**: Backend service definitions (GKE NEGs, internet FQDNs, serverless NEGs)
- **`routing`**: Model-based, header-based, and path-based routing rules
- **`body_based_routing`**: BBR ext\_proc configuration
- **`security`**: Model Armor integration

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

### Step 2: Apply the Artifact Registry module

The BBR ext\_proc image needs an Artifact Registry repository. Apply the registry module first:

```bash
cd terraform/

terraform init
terraform apply -var-file="diy-gateway.tfvars" -auto-approve -target=module.artifact_registry
```

### Step 3: Build and push the BBR ext\_proc image

```bash
BBR_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/images/bbr-ext-proc:latest"

# Configure Docker authentication for Artifact Registry
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Build the image
docker build -t "$BBR_IMAGE" src/bbr-ext-proc-go/

# Push to Artifact Registry
docker push "$BBR_IMAGE"
```

### Step 4: Apply the full Terraform configuration

```bash
terraform apply -var-file="diy-gateway.tfvars" -auto-approve
```

> **Note:** Remove `-auto-approve` if you prefer to review the plan before applying.

### Step 5: Capture Terraform outputs

```bash
export VPC_NAME=$(terraform output -raw vpc_name 2>/dev/null || echo "inference-vpc")
export SUBNET_NAME=$(terraform output -raw subnet_name 2>/dev/null || echo "gke-subnet-us-central1")
GATEWAY_IP=$(terraform output -raw self_managed_gateway_ip 2>/dev/null || echo "pending")

echo "VPC_NAME:   $VPC_NAME"
echo "SUBNET_NAME: $SUBNET_NAME"
echo "Gateway IP:  $GATEWAY_IP"
```

---

## Phase C: Deploy Kubernetes resources

### Step 1: Get GKE credentials

```bash
gcloud container clusters get-credentials "inference-cluster" \
    --region "$REGION" \
    --project "$PROJECT_ID"
```

### Step 2: Swap model kustomizations to the DIY variant

Each model directory contains both a `kustomization.yaml` (GKE variant with InferencePool and EPP) and a `kustomization-diy.yaml` (DIY variant with only deployment, service, and NEG annotation). Swap to the DIY variant:

```bash
cd k8s/

IFS=',' read -ra MODEL_ARRAY <<< "$MODELS"
for m in "${MODEL_ARRAY[@]}"; do
    # Back up the GKE variant
    cp "models/$m/kustomization.yaml" "models/$m/kustomization-gke.yaml.bak"
    # Replace with DIY variant
    cp "models/$m/kustomization-diy.yaml" "models/$m/kustomization.yaml"
done
```

### Step 3: Render the root kustomization.yaml

```bash
# Build the MODELS_RESOURCES block
MODELS_RESOURCES=""
for m in "${MODEL_ARRAY[@]}"; do
    MODELS_RESOURCES+="  - models/$m"$'\n'
done
export MODELS_RESOURCES
export PROJECT_ID

envsubst '$MODELS_RESOURCES $PROJECT_ID' \
    < kustomization-diy.yaml.tmpl \
    > kustomization.yaml
```

### Step 4: Deploy manifests

```bash
kubectl kustomize . | kubectl apply -f -
```

### Step 5: Wait for GKE NEG endpoints

Terraform pre-creates empty zonal GKE NEGs. The GKE NEG controller adopts these NEGs and populates endpoints as pods come up. Wait for endpoints to appear:

```bash
for m in "${MODEL_ARRAY[@]}"; do
    NEG_NAME="${m}-neg"
    for attempt in $(seq 1 60); do
        ENDPOINT_COUNT=$(gcloud compute network-endpoint-groups list-network-endpoints \
            "$NEG_NAME" --project "$PROJECT_ID" \
            --zone="${REGION}-a" \
            --format="value(instance)" 2>/dev/null | wc -l)
        if [ "$ENDPOINT_COUNT" -gt 0 ]; then
            echo "NEG $NEG_NAME has $ENDPOINT_COUNT endpoint(s)"
            break
        fi
        if [ "$attempt" -eq 60 ]; then
            echo "Warning: Timed out waiting for endpoints in $NEG_NAME. Pods may still be starting."
        else
            echo "Waiting for endpoints in $NEG_NAME... (attempt $attempt/60)"
            sleep 5
        fi
    done
done
```

### Step 6: Restore original kustomizations

After deployment, restore the GKE variant kustomizations so the repository stays clean:

```bash
for m in "${MODEL_ARRAY[@]}"; do
    if [ -f "models/$m/kustomization-gke.yaml.bak" ]; then
        mv "models/$m/kustomization-gke.yaml.bak" "models/$m/kustomization.yaml"
    fi
done
```

---

## Validation

### Check pod status

```bash
kubectl get pods --all-namespaces -l app.kubernetes.io/part-of=inference-gateway
```

### Check NEG endpoints

```bash
gcloud compute network-endpoint-groups list-network-endpoints \
    "gemma-3-27b-it-neg" \
    --project "$PROJECT_ID" \
    --zone="${REGION}-a"
```

### Send a test request

The gateway is an internal HTTPS endpoint. Run a test from within the VPC (for example, from a GCE instance or a pod inside the cluster):

```bash
curl -k -X POST "https://diy.internal.YOUR_DOMAIN/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "gemma-3-27b-it",
        "messages": [{"role": "user", "content": "Hello"}]
    }'
```

> **Note:** The load balancer may need a few minutes for health checks to pass before requests succeed.

---

## Adding a new model

Adding a new model to the Self-Managed Gateway requires changes in both Terraform and Kubernetes.

### Terraform: Add a backend service

In your `diy-gateway.tfvars`, add a new entry under `backends.services` and a corresponding routing rule:

```hcl
self_managed_gateway = {
  # ... existing configuration ...

  backends = {
    default = "vertex-ai"
    services = {
      # Existing backends...
      "vertex-ai" = {
        internet_fqdn  = "YOUR_REGION-aiplatform.googleapis.com"
        internet_port  = 443
        protocol       = "HTTPS"
        balancing_mode = "UTILIZATION"
      }
      "gemma-3-27b-it" = {
        gke_neg = {
          name  = "gemma-3-27b-it-neg"
          zones = ["YOUR_REGION-a", "YOUR_REGION-b", "YOUR_REGION-c"]
        }
        protocol     = "HTTP"
        health_check = { port = 8000, path = "/health" }
      }

      # New model backend
      "YOUR_MODEL_NAME" = {
        gke_neg = {
          name  = "YOUR_MODEL_NAME-neg"
          zones = ["YOUR_REGION-a", "YOUR_REGION-b", "YOUR_REGION-c"]
        }
        protocol     = "HTTP"
        health_check = { port = 8000, path = "/health" }
      }
    }
  }

  routing = {
    model_rules = [
      # Existing rules...
      { priority = 10, backend = "vertex-ai", model_prefix = "google/gemini", url_rewrite = { /* ... */ } },
      { priority = 20, backend = "gemma-3-27b-it", model_prefix = "google/gemma" },

      # New model rule
      { priority = 30, backend = "YOUR_MODEL_NAME", model_prefix = "YOUR_MODEL_PREFIX" },
    ]
  }

  # ... rest of configuration ...
}
```

Apply the Terraform changes:

```bash
cd terraform/
terraform apply -var-file="diy-gateway.tfvars"
```

### Kubernetes: Create the model overlay

Create a model directory with the DIY variant kustomization:

```bash
mkdir -p k8s/models/YOUR_MODEL_NAME
```

Create `namespace.yaml`:

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

Create `kustomization-diy.yaml`:

```yaml
# k8s/models/YOUR_MODEL_NAME/kustomization-diy.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - ../base-diy

namespace: YOUR_MODEL_NAME
namePrefix: YOUR_MODEL_NAME-

configMapGenerator:
  - name: model-config
    behavior: replace
    literals:
      - MODEL_NAME=YOUR_MODEL_NAME
      - MODEL_ID=YOUR_ORG/YOUR_MODEL_ID
      - COMPUTE_CLASS=dws-flex-h100
      - NEG_NAME=YOUR_MODEL_NAME-neg
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

patches:
  - target:
      kind: Service
      name: llm-service
    patch: |
      - op: replace
        path: /metadata/annotations/cloud.google.com~1neg
        value: '{"exposed_ports": {"8000":{"name": "YOUR_MODEL_NAME-neg"}}}'
```

Then add the model to `MODELS`, swap kustomizations, re-render, and apply as described in Phase C.

---

## Adding new backends

The `self_managed_gateway.backends.services` map supports four types of backends. Each backend service type is mutually exclusive; use exactly one of `gke_neg`, `internet_fqdn`, or `groups` per service entry.

### GKE NEG backends (pre-created)

Use `gke_neg` when your model server runs on GKE and you want Terraform to pre-create the zonal NEGs. The GKE NEG controller adopts them automatically when the matching Kubernetes Service annotation is applied.

```hcl
"my-gke-model" = {
  gke_neg = {
    name  = "my-gke-model-neg"
    zones = ["us-east4-a", "us-east4-b", "us-east4-c"]
  }
  protocol     = "HTTP"
  health_check = { port = 8000, path = "/health" }
}
```

The Kubernetes Service must include a matching NEG annotation:

```yaml
metadata:
  annotations:
    cloud.google.com/neg: '{"exposed_ports": {"8000":{"name": "my-gke-model-neg"}}}'
```

### Internet FQDN backends

Use `internet_fqdn` to route to external APIs such as Vertex AI, OpenAI, or Anthropic.

```hcl
"vertex-ai" = {
  internet_fqdn  = "us-east4-aiplatform.googleapis.com"
  internet_port  = 443
  protocol       = "HTTPS"
  balancing_mode = "UTILIZATION"
}
```

When routing to Vertex AI, combine this with a `url_rewrite` in your routing rules to transform the OpenAI-compatible path:

```hcl
model_rules = [
  {
    priority     = 10
    backend      = "vertex-ai"
    model_prefix = "google/gemini"
    url_rewrite = {
      host_rewrite        = "us-east4-aiplatform.googleapis.com"
      path_prefix_rewrite = "/v1beta1/projects/YOUR_PROJECT_ID/locations/us-east4/endpoints/openapi/"
    }
  }
]
```

### Serverless NEG backends (Cloud Run, Cloud Functions)

Use `groups` with serverless NEG self-links for Cloud Run services:

```hcl
"my-cloud-run-service" = {
  groups = [
    "projects/YOUR_PROJECT_ID/regions/YOUR_REGION/networkEndpointGroups/my-serverless-neg"
  ]
  protocol       = "HTTPS"
  balancing_mode = "UTILIZATION"
}
```

You create the serverless NEG outside of this module:

```bash
gcloud compute network-endpoint-groups create my-serverless-neg \
    --region=YOUR_REGION \
    --network-endpoint-type=serverless \
    --cloud-run-service=my-cloud-run-service \
    --project=YOUR_PROJECT_ID
```

### Existing NEG backends

Use `groups` to attach any pre-existing NEGs (zonal, hybrid, or internet) that are managed outside of this module:

```hcl
"existing-pool" = {
  groups = [
    "projects/YOUR_PROJECT_ID/zones/us-east4-a/networkEndpointGroups/my-existing-neg",
    "projects/YOUR_PROJECT_ID/zones/us-east4-b/networkEndpointGroups/my-existing-neg"
  ]
  protocol     = "HTTP"
  health_check = { port = 8000, path = "/health" }
}
```

### Backend service options

All backend types support these optional fields:

| Field | Default | Description |
| --- | --- | --- |
| `balancing_mode` | `"RATE"` | `RATE`, `UTILIZATION`, or `CONNECTION` |
| `max_rate_per_endpoint` | `50` | Maximum requests per second per endpoint |
| `capacity_scaler` | `1.0` | Scaling factor (0.0 to 1.0) |
| `timeout_sec` | `90` | Backend timeout in seconds |
| `protocol` | `"HTTP"` | `HTTP`, `HTTPS`, or `HTTP2` |
| `health_check` | `null` | `{ port = 8000, path = "/health" }` |

---

## Routing configuration

The Self-Managed Gateway supports three types of routing rules, all evaluated by priority number (lowest number = highest priority). The Body-Based Router (BBR) `ext_proc` extracts the `model` field from the JSON request body and injects it as an `X-Gateway-Model-Name` header before the load balancer evaluates routing rules.

### How body-based routing works

1. A client sends a POST request with `{"model": "gemma-3-27b-it", ...}` in the body.
2. The load balancer sends the request to the BBR `ext_proc` service via a gRPC Service Extension.
3. The BBR parses the `model` field from the JSON body.
4. The BBR injects `X-Gateway-Model-Name: gemma-3-27b-it` as a request header.
5. The load balancer evaluates routing rules against the injected header.
6. The request is forwarded to the matched backend service.

### Model-based routing (`model_rules`)

Route requests based on the model name extracted from the request body. Uses prefix matching against the `X-Gateway-Model-Name` header.

```hcl
routing = {
  model_rules = [
    {
      priority     = 10
      backend      = "vertex-ai"
      model_prefix = "google/gemini"
      url_rewrite = {
        host_rewrite        = "YOUR_REGION-aiplatform.googleapis.com"
        path_prefix_rewrite = "/v1beta1/projects/YOUR_PROJECT_ID/locations/YOUR_REGION/endpoints/openapi/"
      }
    },
    {
      priority     = 20
      backend      = "gemma-3-27b-it"
      model_prefix = "google/gemma"
    }
  ]
}
```

### Header-based routing (`header_rules`)

Route requests based on arbitrary header values. Supports `exact`, `prefix`, and `regex` match types.

```hcl
routing = {
  header_rules = [
    {
      priority    = 10
      backend     = "vertex-ai"
      header_name = "X-Gateway-Model-Name"
      match_type  = "exact"
      match_value = "gemini-3.1-pro-preview"
    },
    {
      priority    = 20
      backend     = "gke-pool"
      header_name = "X-Gateway-Model-Name"
      match_type  = "exact"
      match_value = "gemma-3-27b-it"
    }
  ]
}
```

### Path-based routing (`path_rules`)

Route requests based on the URL path prefix.

```hcl
routing = {
  path_rules = [
    {
      priority   = 6
      backend    = "gemma-3-27b-it"
      path_match = "/security/"
      url_rewrite = {
        path_prefix_rewrite = "/"
      }
    }
  ]
}
```

### URL rewriting for Vertex AI

When routing to Vertex AI, rewrite both the host and path to match the Vertex AI prediction endpoint format:

```hcl
model_rules = [
  {
    priority     = 10
    backend      = "vertex-ai"
    model_prefix = "google/gemini"
    url_rewrite = {
      host_rewrite        = "YOUR_REGION-aiplatform.googleapis.com"
      path_prefix_rewrite = "/v1beta1/projects/YOUR_PROJECT_ID/locations/YOUR_REGION/endpoints/openapi/"
    }
  }
]
```

This transforms requests from:

```text
POST https://diy.internal.YOUR_DOMAIN/v1/chat/completions
```

To:

```text
POST https://YOUR_REGION-aiplatform.googleapis.com/v1beta1/projects/YOUR_PROJECT_ID/locations/YOUR_REGION/endpoints/openapi/chat/completions
```

### A/B testing with `X-Backend-Type`

The gateway automatically creates high-priority routes for the `X-Backend-Type` header. When this header is present and matches a backend service name, the request is routed directly to that backend, bypassing all other routing rules.

Define both backends:

```hcl
backends = {
  default = "gke-stable"
  services = {
    "gke-stable"       = { gke_neg = { name = "stable-neg", zones = ["us-east4-a"] }, protocol = "HTTP" }
    "gke-experimental" = { gke_neg = { name = "canary-neg", zones = ["us-east4-a"] }, protocol = "HTTP" }
  }
}
```

Test with the override header:

```bash
# Normal request (routes via model rules or default)
curl -k -X POST "https://diy.internal.YOUR_DOMAIN/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model": "gemma-3-27b-it", "messages": [{"role": "user", "content": "Hello"}]}'

# Force experimental backend
curl -k -X POST "https://diy.internal.YOUR_DOMAIN/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "X-Backend-Type: gke-experimental" \
    -d '{"model": "gemma-3-27b-it", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Priority evaluation order

The gateway evaluates rules in the following order:

1. **Direct backend overrides:** `X-Backend-Type` header matches (highest priority).
2. **Model matches:** `model_rules` based on request body (user-defined priority).
3. **Header matches:** `header_rules` (user-defined priority).
4. **Path matches:** `path_rules` (user-defined priority).
5. **Default:** `backends.default` service.

---

## Serverless and internet backends

### Internet backends for externally hosted models

Use internet FQDN backends to route to managed model APIs such as Vertex AI, OpenAI, or Anthropic. Define the backend with the API hostname and add a routing rule with a URL rewrite:

```hcl
backends = {
  services = {
    "vertex-ai" = {
      internet_fqdn  = "YOUR_REGION-aiplatform.googleapis.com"
      internet_port  = 443
      protocol       = "HTTPS"
      balancing_mode = "UTILIZATION"
    }
  }
}
```

### Serverless backends via Cloud Run

Create a serverless NEG for your Cloud Run service, then reference it in the `groups` field:

```bash
# Create the serverless NEG
gcloud compute network-endpoint-groups create my-run-neg \
    --region=YOUR_REGION \
    --network-endpoint-type=serverless \
    --cloud-run-service=my-inference-service \
    --project=YOUR_PROJECT_ID
```

```hcl
backends = {
  services = {
    "my-run-service" = {
      groups = [
        "projects/YOUR_PROJECT_ID/regions/YOUR_REGION/networkEndpointGroups/my-run-neg"
      ]
      protocol       = "HTTPS"
      balancing_mode = "UTILIZATION"
    }
  }
}
```

### Hybrid NEG patterns

For on-premises or multi-cloud model servers, create hybrid connectivity NEGs and reference them via `groups`. This pattern lets you route inference traffic to endpoints outside of Google Cloud while keeping a unified gateway interface.
