#!/bin/bash
# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Template-driven deployment pipeline for Inference Gateway Solutions.
#
# Three-phase pipeline:
#   Phase A: envsubst renders .tfvars.tmpl -> .tfvars
#   Phase B: terraform apply -> capture outputs
#   Phase C: envsubst renders kustomization.yaml.tmpl -> kubectl apply -k
#
# Templates:
#   terraform/gke-gateway.tfvars.tmpl
#   terraform/diy-gateway.tfvars.tmpl
#   k8s/kustomization-gke.yaml.tmpl
#   k8s/kustomization-diy.yaml.tmpl
#   k8s/features/model-armor/model-armor.yaml.tmpl
#   k8s/features/unified-extension/unified-extension.yaml.tmpl

set -e

# Add local bin to path
export PATH=$PATH:$HOME/bin

# ============================================================================
# Section 1: Configuration & Helpers
# ============================================================================
BOLD=$(tput bold 2>/dev/null || true)
NORMAL=$(tput sgr0 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
PROJECT_ROOT=$(pwd)

log() {
	echo "${BOLD}${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NORMAL}"
}

error() {
	echo "${BOLD}${RED}[ERROR] $1${NORMAL}" >&2
	exit 1
}

usage() {
	echo "Usage: $0 [options]"
	echo ""
	echo "Options:"
	echo "  -p, --project <id>       Google Cloud Project ID"
	echo "  -r, --region <region>    Region (default: us-east4)"
	echo "  -z, --dns-zone <name>    Cloud DNS Managed Zone Name"
	echo "  -t, --type <gke|diy>     Gateway Type (gke or diy)"
	echo "  -k, --hf-token <token>   Hugging Face API Token"
	echo "  -s, --skip-infra         Skip API enablement and Terraform deployment"
	echo "  -m, --models <list>      Comma-separated list of models to deploy (default: gemma-3-27b-it)"
	echo "  -f, --features <list>    Comma-separated list of features to enable (custom-metrics,semantic-cache,unified-extension,model-armor)"
	echo "  --dry-run                Render templates and validate without running terraform/kubectl"
	echo "  -h, --help               Show this help message"
	echo ""
	exit 0
}

# --- Flag Parsing ---
SKIP_INFRA=false
DRY_RUN=false
MODELS="gemma-3-27b-it"
FEATURES="custom-metrics"
while [[ $# -gt 0 ]]; do
	case "$1" in
	-p | --project)
		PROJECT_ID="$2"
		shift 2
		;;
	-r | --region)
		REGION="$2"
		shift 2
		;;
	-z | --dns-zone)
		DNS_ZONE_NAME="$2"
		shift 2
		;;
	-t | --type)
		GATEWAY_TYPE="$2"
		shift 2
		;;
	-k | --hf-token)
		HF_TOKEN="$2"
		shift 2
		;;
	-s | --skip-infra)
		SKIP_INFRA=true
		shift
		;;
	-m | --models)
		MODELS="$2"
		shift 2
		;;
	-f | --features)
		FEATURES="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		echo "Unknown option: $1"
		usage
		;;
	esac
done

# Check prerequisites
REQUIRED_CMDS="gcloud terraform kubectl helm kustomize envsubst"
if [ "$DRY_RUN" = true ]; then
	REQUIRED_CMDS="envsubst terraform"
fi
for cmd in $REQUIRED_CMDS; do
	if ! command -v "$cmd" &>/dev/null; then
		error "$cmd is not installed. Please install it before running this script."
	fi
done

# ============================================================================
# Section 1b: Input Gathering
# ============================================================================
log "Gathering deployment information..."

# Auto-detect non-interactive mode if no TTY is attached
if [ -z "$NON_INTERACTIVE" ] && [ ! -t 0 ]; then
	NON_INTERACTIVE=true
	log "Non-interactive mode auto-detected."
fi

# Fallback chain for Project ID
PROJECT_ID=${PROJECT_ID:-$GOOGLE_PROJECT}
PROJECT_ID=${PROJECT_ID:-$GOOGLE_CLOUD_PROJECT}
if [ -z "$PROJECT_ID" ]; then
	log "Project ID not found in environment, checking gcloud config..."
	PROJECT_ID=$(gcloud config get-value project --quiet 2>/dev/null)
fi

if [ -z "$PROJECT_ID" ]; then
	if [ -n "$NON_INTERACTIVE" ]; then
		error "PROJECT_ID is required but not set in flags or environment."
	fi
	read -rp "Enter Google Cloud Project ID: " PROJECT_ID
fi
log "Using Project ID: $PROJECT_ID"

# Fallback for Region
REGION=${REGION:-$GOOGLE_CLOUD_REGION}
REGION=${REGION:-$GOOGLE_REGION}
if [ -z "$REGION" ]; then
	if [ -n "$NON_INTERACTIVE" ]; then
		REGION="us-east4"
	else
		read -rp "Enter Region (default: us-east4): " REGION
		REGION=${REGION:-us-east4}
	fi
fi
log "Using Region: $REGION"

if [ -z "$DNS_ZONE_NAME" ]; then
	echo "This deployment requires an existing Cloud DNS Managed Zone."
	read -rp "Enter Cloud DNS Managed Zone Name: " DNS_ZONE_NAME
fi
log "Using DNS Zone: $DNS_ZONE_NAME"

# Validate DNS Zone existence (skip in dry-run)
if [ "$DRY_RUN" = false ]; then
	log "Validating DNS Zone '$DNS_ZONE_NAME' in project '$PROJECT_ID'..."
	while ! gcloud dns managed-zones describe "$DNS_ZONE_NAME" --project "$PROJECT_ID" --quiet &>/dev/null; do
		error_msg=$(gcloud dns managed-zones describe "$DNS_ZONE_NAME" --project "$PROJECT_ID" --quiet 2>&1)
		echo "${BOLD}${RED}Error: Managed Zone '$DNS_ZONE_NAME' not found in project $PROJECT_ID.${NORMAL}"
		echo "Details: $error_msg"
		if [ -n "$NON_INTERACTIVE" ]; then
			error "DNS Zone validation failed in non-interactive mode."
		fi
		read -rp "Please enter the CORRECT Cloud DNS Managed Zone Name: " DNS_ZONE_NAME
	done
fi

if [ -z "$HF_TOKEN" ]; then
	if [ -n "$NON_INTERACTIVE" ]; then
		HF_TOKEN=""
	else
		read -rp "Enter Hugging Face API Token (optional, press Enter to skip): " HF_TOKEN
	fi
fi

if [ -z "$GATEWAY_TYPE" ]; then
	if [ -n "$NON_INTERACTIVE" ]; then
		error "GATEWAY_TYPE must be provided in non-interactive mode."
	fi
	echo ""
	echo "Select Gateway Option:"
	echo "1) GKE Inference Gateway (GKE-native)"
	echo "2) DIY Gateway (Self-managed Load Balancer)"
	read -rp "Choice [1-2]: " CHOICE

	case $CHOICE in
	1) GATEWAY_TYPE="gke" ;;
	2) GATEWAY_TYPE="diy" ;;
	*) error "Invalid choice." ;;
	esac
fi

case $GATEWAY_TYPE in
gke) TFVARS_FILE="gke-gateway.tfvars" ;;
diy) TFVARS_FILE="diy-gateway.tfvars" ;;
*) error "Invalid gateway type: $GATEWAY_TYPE. Use 'gke' or 'diy'." ;;
esac

# ============================================================================
# Section 2: Resolve Derived Variables
# ============================================================================
log "Resolving derived variables..."

# Domain resolution (skip gcloud call in dry-run, use fallback)
if [ "$DRY_RUN" = false ]; then
	DOMAIN_NAME=$(gcloud dns managed-zones describe "$DNS_ZONE_NAME" --project "$PROJECT_ID" --format="value(dnsName)" --quiet 2>/dev/null | sed 's/\.$//')
fi
if [ -z "$DOMAIN_NAME" ]; then
	DOMAIN_NAME=$(echo "$DNS_ZONE_NAME" | sed 's/-/./g')
	log "Using derived domain: $DOMAIN_NAME"
fi
log "Resolved Domain Name: $DOMAIN_NAME"

# Gateway host
if [ "$GATEWAY_TYPE" == "gke" ]; then
	export GATEWAY_HOST="gateway.internal.$DOMAIN_NAME"
else
	export GATEWAY_HOST="diy.internal.$DOMAIN_NAME"
fi
log "Gateway Host: $GATEWAY_HOST"

# HuggingFace token
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

# Convert models list to Terraform list format: ["model1", "model2"]
MODEL_NAMESPACES_TF="["
IFS=',' read -ra MODEL_ARRAY <<<"$MODELS"
for i in "${!MODEL_ARRAY[@]}"; do
	MODEL_NAMESPACES_TF+="\"${MODEL_ARRAY[$i]}\""
	if [ "$i" -lt $((${#MODEL_ARRAY[@]} - 1)) ]; then
		MODEL_NAMESPACES_TF+=", "
	fi
done
MODEL_NAMESPACES_TF+="]"
export MODEL_NAMESPACES_TF

# Build RESOURCES_BLOCK for kustomization-gke.yaml.tmpl
RESOURCES_BLOCK=""
for m in "${MODEL_ARRAY[@]}"; do
	RESOURCES_BLOCK+="  - models/$m"$'\n'
done

IFS=',' read -ra FEATURE_ARRAY <<<"$FEATURES"

# Validate mutual exclusivity: semantic-cache and unified-extension both include
# the semantic-cache chain and cannot be enabled simultaneously.
HAS_SC=false
HAS_UE=false
for f in "${FEATURE_ARRAY[@]}"; do
	[[ $f == "semantic-cache" ]] && HAS_SC=true
	[[ $f == "unified-extension" ]] && HAS_UE=true
done
if [ "$HAS_SC" = true ] && [ "$HAS_UE" = true ]; then
	error "Features 'semantic-cache' and 'unified-extension' are mutually exclusive (both include the semantic-cache chain)."
fi

export RESOURCES_BLOCK

# Build COMPONENTS_BLOCK for kustomization-gke.yaml.tmpl
COMPONENTS_BLOCK=""
HAS_COMPONENTS=false
for f in "${FEATURE_ARRAY[@]}"; do
	if [ -d "$PROJECT_ROOT/k8s/features/$f" ]; then
		if [ "$HAS_COMPONENTS" = false ]; then
			COMPONENTS_BLOCK+=$'\n'"components:"$'\n'
			HAS_COMPONENTS=true
		fi
		COMPONENTS_BLOCK+="  - features/$f"$'\n'
	fi
done
export COMPONENTS_BLOCK

# Build MODELS_RESOURCES for kustomization-diy.yaml.tmpl
MODELS_RESOURCES=""
for m in "${MODEL_ARRAY[@]}"; do
	MODELS_RESOURCES+="  - models/$m"$'\n'
done
export MODELS_RESOURCES

# Static IP name (resolved from Terraform output after Phase B, fallback for dry-run/skip-infra)
export STATIC_IP_NAME="${STATIC_IP_NAME:-igw-internal-gateway-ip}"

# Proxy name is always the CRD-created proxy
export SEMANTIC_PROXY_NAME="apigee-cache-backend"

# Export all variables needed by envsubst
export PROJECT_ID REGION DOMAIN_NAME DNS_ZONE_NAME VPC_NAME SUBNET_NAME

# ============================================================================
# Section 3: Phase A - Template Rendering (tfvars)
# ============================================================================
log "Phase A: Rendering Terraform configuration from template..."

TEMPLATE_FILE="${GATEWAY_TYPE}-gateway.tfvars.tmpl"
if [ ! -f "$PROJECT_ROOT/terraform/$TEMPLATE_FILE" ]; then
	error "Template not found: terraform/$TEMPLATE_FILE"
fi

# Use restricted envsubst to avoid clobbering HCL interpolation syntax
ENVSUBST_VARS='$PROJECT_ID $REGION $DOMAIN_NAME $DNS_ZONE_NAME $HUGGINGFACE_TOKEN $ENABLE_HF $ENABLE_MODEL_ARMOR $ENABLE_SEMANTIC_CACHE $MODEL_NAMESPACES_TF $VPC_NAME'
envsubst "$ENVSUBST_VARS" \
	<"$PROJECT_ROOT/terraform/$TEMPLATE_FILE" \
	>"$PROJECT_ROOT/terraform/$TFVARS_FILE"

log "Generated: terraform/$TFVARS_FILE"

# Validation: check for unresolved placeholders
if grep -qP '\$\{[A-Z_]+\}' "$PROJECT_ROOT/terraform/$TFVARS_FILE"; then
	UNRESOLVED=$(grep -oP '\$\{[A-Z_]+\}' "$PROJECT_ROOT/terraform/$TFVARS_FILE" | sort -u | tr '\n' ' ')
	error "Unresolved placeholders in terraform/$TFVARS_FILE: $UNRESOLVED"
fi
log "Validation passed: no unresolved placeholders in tfvars."

if [ "$DRY_RUN" = true ]; then
	log "Dry-run: validating Terraform configuration..."
	cd "$PROJECT_ROOT/terraform"
	terraform init -backend=false >/dev/null 2>&1 || true
	terraform validate
	log "Dry-run: Terraform validation passed."
fi

# ============================================================================
# Section 4: Phase B - Terraform Apply
# ============================================================================
if [ "$DRY_RUN" = true ]; then
	log "Dry-run: skipping Phase B (Terraform apply)."
	# Set fallback values for Phase C
	export APIGEE_ENV="apis-prod"
	export MODEL_ARMOR_TEMPLATE="projects/$PROJECT_ID/locations/$REGION/templates/default-safety-template"
	export VPC_NAME="${VPC_NAME:-inference-vpc}"
	export SUBNET_NAME="${SUBNET_NAME:-gke-subnet-us-central1}"
elif [ "$SKIP_INFRA" = true ]; then
	log "Skipping infrastructure deployment (--skip-infra)."
	export APIGEE_ENV="apis-prod"
	export MODEL_ARMOR_TEMPLATE="projects/$PROJECT_ID/locations/$REGION/templates/default-safety-template"
	export VPC_NAME="${VPC_NAME:-inference-vpc}"
	export SUBNET_NAME="${SUBNET_NAME:-gke-subnet-us-central1}"
else
	# --- API Enablement ---
	log "Enabling required Google Cloud APIs in project $PROJECT_ID..."
	gcloud config set project "$PROJECT_ID"
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

	cd "$PROJECT_ROOT/terraform"

	log "Initializing Terraform..."
	terraform init

	if [ "$GATEWAY_TYPE" == "diy" ]; then
		log "Applying artifact registry module..."
		terraform apply -var-file="$TFVARS_FILE" -auto-approve -target=module.artifact_registry

		log "Building and pushing BBR ext_proc image..."
		BBR_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/images/bbr-ext-proc:latest"
		gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
		docker build -t "$BBR_IMAGE" "$PROJECT_ROOT/src/bbr-ext-proc-go/"
		docker push "$BBR_IMAGE"
		log "BBR ext_proc image pushed: $BBR_IMAGE"
	fi

	log "Applying complete Terraform configuration..."
	terraform apply -var-file="$TFVARS_FILE" -auto-approve

	# Capture outputs for Phase C
	log "Capturing Terraform outputs..."
	export APIGEE_ENV
	APIGEE_ENV=$(terraform output -json apigee_environments 2>/dev/null | grep -o '"[^"]*":' | head -1 | tr -d '":' || true)
	if [ -z "$APIGEE_ENV" ]; then
		log "Warning: APIGEE_ENV not found in outputs, using default: apis-prod"
		APIGEE_ENV="apis-prod"
	fi
	export MODEL_ARMOR_TEMPLATE
	MODEL_ARMOR_TEMPLATE=$(terraform output -raw model_armor_template_name 2>/dev/null || true)
	if [ -z "$MODEL_ARMOR_TEMPLATE" ]; then
		log "Warning: MODEL_ARMOR_TEMPLATE not captured, using fallback"
		MODEL_ARMOR_TEMPLATE="projects/${PROJECT_ID}/locations/${REGION}/templates/default-safety-template"
	fi

	# Resolve static IP name from Terraform output
	TF_STATIC_IP_NAME=$(terraform output -raw internal_gateway_ip_name 2>/dev/null || true)
	if [ -n "$TF_STATIC_IP_NAME" ]; then
		export STATIC_IP_NAME="$TF_STATIC_IP_NAME"
	fi
	log "Using Static IP Name: $STATIC_IP_NAME"

	# Resolve VPC and subnet names from Terraform output
	VPC_NAME=$(terraform output -raw vpc_name 2>/dev/null || echo "inference-vpc")
	SUBNET_NAME=$(terraform output -raw subnet_name 2>/dev/null || echo "gke-subnet-us-central1")
	export VPC_NAME SUBNET_NAME
	log "Using VPC Name: $VPC_NAME"
	log "Using Subnet Name: $SUBNET_NAME"
fi

# ============================================================================
# Section 5: Phase C - Kubernetes Deployment
# ============================================================================

if [ "$GATEWAY_TYPE" == "gke" ]; then
	# ------------------------------------------------------------------
	# GKE Inference Gateway
	# ------------------------------------------------------------------
	log "Phase C: Deploying GKE Inference Gateway..."

	if [ "$DRY_RUN" = false ]; then
		gcloud container clusters get-credentials "inference-cluster" --region "$REGION" --project "$PROJECT_ID"
	fi

	cd "$PROJECT_ROOT/k8s"

	# --- Render feature templates with envsubst ---
	FEATURE_ENVSUBST_VARS='$REGION $PROJECT_ID $MODEL_ARMOR_TEMPLATE $SEMANTIC_PROXY_NAME'

	if [ -f "features/model-armor/model-armor.yaml.tmpl" ]; then
		log "Rendering model-armor.yaml from template..."
		envsubst "$FEATURE_ENVSUBST_VARS" \
			<features/model-armor/model-armor.yaml.tmpl \
			>features/model-armor/model-armor.yaml
	fi

	if [ -f "features/unified-extension/unified-extension.yaml.tmpl" ]; then
		log "Rendering unified-extension.yaml from template..."
		envsubst "$FEATURE_ENVSUBST_VARS" \
			<features/unified-extension/unified-extension.yaml.tmpl \
			>features/unified-extension/unified-extension.yaml
	fi

	# --- Render Helm charts (if semantic-cache is enabled) ---
	if [[ $FEATURES == *"semantic-cache"* ]] || [[ $FEATURES == *"unified-extension"* ]]; then
		log "Rendering Apigee Operator Helm charts..."
		helm template apigee-apim-crds ./features/semantic-cache-infra/charts/apigee-apim-operator-crds-1.1.0/apigee-apim-operator-crds \
			--namespace apim --include-crds >features/semantic-cache-infra/apigee-apim-operator-crds.gen.yaml

		helm template apigee-apim-operator ./features/semantic-cache-infra/charts/apigee-apim-operator-helm-1.1.0/apigee-apim-operator-helm \
			--namespace apim \
			--set projectId="$PROJECT_ID" \
			--set serviceAccount="apigee-apim-gsa@$PROJECT_ID.iam.gserviceaccount.com" \
			--set apigeeOrg="$PROJECT_ID" \
			--set generateEnv=false >features/semantic-cache-infra/apigee-apim-operator-helm.gen.yaml
	fi

	# --- Render root kustomization from template ---
	log "Rendering kustomization.yaml from template..."
	KUST_ENVSUBST_VARS='$RESOURCES_BLOCK $COMPONENTS_BLOCK $GATEWAY_HOST $PROJECT_ID $REGION $STATIC_IP_NAME $APIGEE_ENV $MODEL_ARMOR_TEMPLATE $SEMANTIC_PROXY_NAME $VPC_NAME $SUBNET_NAME'
	envsubst "$KUST_ENVSUBST_VARS" \
		<kustomization-gke.yaml.tmpl \
		>kustomization.yaml

	if [ "$DRY_RUN" = true ]; then
		log "Dry-run: validating kustomize output..."
		kubectl kustomize . >/dev/null
		log "Dry-run: kustomize validation passed."

		# Check for unresolved placeholders in rendered output
		RENDERED=$(kubectl kustomize .)
		if echo "$RENDERED" | grep -qP 'PLACEHOLDER_'; then
			echo "$RENDERED" | grep -oP 'PLACEHOLDER_\w+' | sort -u
			error "Unresolved PLACEHOLDER_ values found in rendered manifests."
		fi
		if echo "$RENDERED" | grep -q 'PLACEHOLDER_PROJECT_ID'; then
			error "Hardcoded project ID found in rendered manifests."
		fi
		log "Dry-run validation complete. All templates rendered successfully."
		cd "$PROJECT_ROOT"
		exit 0
	fi

	# --- Deploy to GKE ---
	if [[ $FEATURES == *"semantic-cache"* ]] || [[ $FEATURES == *"unified-extension"* ]]; then
		log "Deploying CRDs and waiting for establishment..."
		kubectl apply -f features/semantic-cache-infra/apigee-apim-operator-crds.gen.yaml
		kubectl apply -k crds/
		sleep 20
	else
		log "Deploying CRDs and waiting for establishment..."
		kubectl apply -k crds/
		sleep 20
	fi

	log "Deploying custom-metrics adapter..."
	kubectl apply -k custom-metrics/

	log "Deploying inference gateway resources..."
	kubectl kustomize . | kubectl apply -f -

	# --- Wait for Apigee operator and deploy semantic cache proxy ---
	if [[ $FEATURES == *"semantic-cache"* ]] || [[ $FEATURES == *"unified-extension"* ]]; then
		log "Waiting for Apigee Operator to be ready..."
		kubectl wait --for=condition=Available deployment/apigee-apim-operator -n apim --timeout=300s || true

		log "Waiting for ApigeeBackendService to be established..."
		for i in {1..60}; do
			STATE=$(kubectl get apigeebackendservice apigee-cache-backend -o jsonpath='{.status.currentState}' 2>/dev/null || echo "Unknown")
			if [ "$STATE" == "CREATED" ]; then
				log "ApigeeBackendService is established (currentState: $STATE)"
				sleep 30
				break
			fi
			if [ $i -eq 60 ]; then
				log "Warning: Timed out waiting for ApigeeBackendService to reach CREATED state. Proceeding anyway..."
			else
				echo "Waiting for ApigeeBackendService... (attempt $i/60, current state: $STATE)"
				sleep 10
			fi
		done

		# --- Semantic Cache Proxy Deployment ---
		log "Deploying semantic cache proxy to Apigee..."

		cd "$PROJECT_ROOT/terraform"
		PROJECT_NUMBER=$(terraform output -raw foundation_project_number 2>/dev/null)
		VERTEX_ENDPOINT_DOMAIN=$(terraform output -raw vertex_ai_index_endpoint_domain 2>/dev/null)
		VERTEX_ENDPOINT_ID=$(terraform output -raw vertex_ai_endpoint_numeric_id 2>/dev/null)
		VERTEX_INDEX_ID=$(terraform output -raw vertex_ai_index_numeric_id 2>/dev/null)
		VERTEX_DEPLOYED_INDEX_ID=$(terraform output -raw vertex_ai_deployed_index_id 2>/dev/null)

		PROXY_BUNDLE_NAME="apigee-cache-backend"
		PROXY_SA="apigee-proxy-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
		SIMILARITY_THRESHOLD="0.95"
		TTL_SECONDS="600"
		EMBEDDING_MODEL="gemini-embedding-001"

		POLICY_SRC="$PROJECT_ROOT/terraform/modules/apigee-semantic-proxy"
		STAGING="/tmp/proxy-bundle-$$"
		mkdir -p "$STAGING/apiproxy/policies" "$STAGING/apiproxy/proxies"

		cp "$POLICY_SRC/bundle-extension/apiproxy/proxies/default.xml" "$STAGING/apiproxy/proxies/"
		cp "$POLICY_SRC/bundle-extension/apiproxy/policies/AM-Set-Cache-Headers.xml" "$STAGING/apiproxy/policies/"
		cp "$POLICY_SRC/bundle-extension/apiproxy/policies/EV-Extract-Body-Debug.xml" "$STAGING/apiproxy/policies/"
		cp "$POLICY_SRC/bundle-extension/apiproxy/policies/RF-Return-Cached-Response.xml" "$STAGING/apiproxy/policies/"

		cat >"$STAGING/apiproxy/$PROXY_BUNDLE_NAME.xml" <<XMLEOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="$PROXY_BUNDLE_NAME">
  <DisplayName>$PROXY_BUNDLE_NAME</DisplayName>
  <Description>Semantic caching proxy deployed via deploy.sh</Description>
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

		# Render SCL template (sed on Terraform .tftpl files - out of scope for envsubst conversion)
		sed -e "s/\${region}/$REGION/g" \
			-e "s/\${project_number}/$PROJECT_NUMBER/g" \
			-e "s/\${embedding_model}/$EMBEDDING_MODEL/g" \
			-e "s/\${public_endpoint_domain}/$VERTEX_ENDPOINT_DOMAIN/g" \
			-e "s/\${endpoint_numeric_id}/$VERTEX_ENDPOINT_ID/g" \
			-e "s/\${deployed_index_id}/$VERTEX_DEPLOYED_INDEX_ID/g" \
			-e "s/\${similarity_threshold}/$SIMILARITY_THRESHOLD/g" \
			"$POLICY_SRC/templates/policies/SCL-Semantic-Cache-Lookup.xml.tftpl" \
			>"$STAGING/apiproxy/policies/SCL-Semantic-Cache-Lookup.xml"

		# Render SCP template
		sed -e "s/\${region}/$REGION/g" \
			-e "s/\${project_number}/$PROJECT_NUMBER/g" \
			-e "s/\${index_numeric_id}/$VERTEX_INDEX_ID/g" \
			-e "s/\${ttl_seconds}/$TTL_SECONDS/g" \
			"$POLICY_SRC/templates/policies/SCP-Semantic-Cache-Populate.xml.tftpl" \
			>"$STAGING/apiproxy/policies/SCP-Semantic-Cache-Populate.xml"

		cd "$STAGING"
		zip -r /tmp/proxy-bundle.zip apiproxy/

		log "Uploading proxy bundle to Apigee..."
		TOKEN=$(gcloud auth print-access-token)

		UPLOAD_RESPONSE=$(curl -s -X POST \
			"https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/apis?name=${PROXY_BUNDLE_NAME}&action=import" \
			-H "Authorization: Bearer $TOKEN" \
			-H "Content-Type: multipart/form-data" \
			-F "file=@/tmp/proxy-bundle.zip")

		REVISION=$(echo "$UPLOAD_RESPONSE" | grep -o '"revision": *"[^"]*"' | cut -d'"' -f4)
		log "Uploaded proxy revision: $REVISION"

		log "Deploying proxy revision $REVISION..."
		curl -s -X POST \
			"https://apigee.googleapis.com/v1/organizations/${PROJECT_ID}/environments/${APIGEE_ENV}/apis/${PROXY_BUNDLE_NAME}/revisions/${REVISION}/deployments?override=true" \
			-H "Authorization: Bearer $TOKEN" \
			-H "Content-Type: application/json" \
			-d "{\"serviceAccount\": \"${PROXY_SA}\"}"

		cd "$PROJECT_ROOT"
		log "Semantic cache proxy deployed successfully!"
	fi

	log "Deployment complete! It may take a few minutes for the Load Balancer to provision."
	log "Access your gateway at: https://$GATEWAY_HOST"

else
	# ------------------------------------------------------------------
	# DIY Inference Gateway - Phase 2
	# ------------------------------------------------------------------
	log "Phase C: Deploying DIY Inference Gateway..."

	if [ "$DRY_RUN" = false ]; then
		gcloud container clusters get-credentials "inference-cluster" --region "$REGION" --project "$PROJECT_ID"
	fi

	cd "$PROJECT_ROOT/k8s"

	# --- Swap model kustomization to DIY variant ---
	IFS=',' read -ra MODEL_ARRAY <<<"$MODELS"
	for m in "${MODEL_ARRAY[@]}"; do
		DIY_KUST="models/$m/kustomization-diy.yaml"
		GKE_KUST="models/$m/kustomization.yaml"
		if [ ! -f "$DIY_KUST" ]; then
			error "DIY kustomization not found: $DIY_KUST"
		fi
		log "Swapping kustomization for $m to DIY variant..."
		cp "$GKE_KUST" "models/$m/kustomization-gke.yaml.bak" || error "Failed to backup GKE kustomization for $m"
		cp "$DIY_KUST" "$GKE_KUST" || error "Failed to swap DIY kustomization for $m"
	done

	# --- Render root kustomization from template ---
	log "Rendering kustomization.yaml from template..."
	envsubst '$MODELS_RESOURCES $PROJECT_ID' \
		<kustomization-diy.yaml.tmpl \
		>kustomization.yaml

	if [ "$DRY_RUN" = true ]; then
		log "Dry-run: validating kustomize output..."
		kubectl kustomize . >/dev/null
		log "Dry-run: kustomize validation passed."

		# Restore original kustomizations
		for m in "${MODEL_ARRAY[@]}"; do
			if [ -f "models/$m/kustomization-gke.yaml.bak" ]; then
				mv "models/$m/kustomization-gke.yaml.bak" "models/$m/kustomization.yaml"
			fi
		done
		log "Dry-run validation complete. All templates rendered successfully."
		cd "$PROJECT_ROOT"
		exit 0
	fi

	# --- Deploy manifests ---
	log "Deploying DIY model manifests to GKE..."
	kubectl kustomize . | kubectl apply -f -

	# --- Wait for GKE NEG controller to populate endpoints ---
	# GKE NEGs were pre-created by Terraform. The GKE NEG controller adopts them
	# and populates endpoints as pods come up. No second terraform apply needed.
	log "GKE NEGs pre-created by Terraform. Waiting for endpoints..."
	for m in "${MODEL_ARRAY[@]}"; do
		NEG_NAME="${m}-neg"
		for attempt in $(seq 1 60); do
			ENDPOINT_COUNT=$(gcloud compute network-endpoint-groups list-network-endpoints \
				"$NEG_NAME" --project "$PROJECT_ID" \
				--zone="${REGION}-a" \
				--format="value(instance)" 2>/dev/null | wc -l)
			if [ "$ENDPOINT_COUNT" -gt 0 ]; then
				log "NEG $NEG_NAME has $ENDPOINT_COUNT endpoint(s)"
				break
			fi
			if [ "$attempt" -eq 60 ]; then
				log "Warning: Timed out waiting for endpoints in $NEG_NAME. Pods may still be starting."
			else
				echo "  Waiting for endpoints in $NEG_NAME... (attempt $attempt/60)"
				sleep 5
			fi
		done
	done

	# --- Restore original kustomizations ---
	cd "$PROJECT_ROOT/k8s"
	for m in "${MODEL_ARRAY[@]}"; do
		if [ -f "models/$m/kustomization-gke.yaml.bak" ]; then
			mv "models/$m/kustomization-gke.yaml.bak" "models/$m/kustomization.yaml"
		fi
	done

	# --- Print summary ---
	cd "$PROJECT_ROOT/terraform"
	GATEWAY_IP=$(terraform output -raw self_managed_gateway_ip 2>/dev/null || echo "pending")

	log "=============================================="
	log "DIY Inference Gateway Deployment Complete!"
	log "=============================================="
	log ""
	log "Gateway Host: $GATEWAY_HOST"
	log "Gateway IP:   $GATEWAY_IP"
	log "Gateway URL:  https://$GATEWAY_HOST"
	log ""
	log "Deployed models: $MODELS"
	log ""
	log "Test with:"
	log "  curl -k -X POST https://$GATEWAY_HOST/v1/chat/completions \\"
	log "    -H 'Content-Type: application/json' \\"
	log "    -d '{\"model\": \"gemma-3-27b-it\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
	log ""
	log "It may take a few minutes for the Load Balancer health checks to pass."
	log ""
	log "To add more models, see: terraform/modules/diy-inference-gateway/README.md"
fi

# ============================================================================
# Section 6: Summary
# ============================================================================
log "You can test your deployment using: GATEWAY_HOST=$GATEWAY_HOST ./test_endpoints.sh"

cd "$PROJECT_ROOT"
log "Deployment process finished successfully."
