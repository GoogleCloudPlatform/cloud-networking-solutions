# Securing Cross-Cloud Agentic Enterprise Deployments

Supporting code for the
[Governing agentic workloads with Agent Gateway on Gemini Enterprise Agent Platform](https://codelabs.developers.google.com/cloudnet-agent-gateway)
codelab.



A multi-tool ADK mortgage agent runs on Vertex AI Agent Runtime and reaches
three internal MCP servers (`legacy-dms`, `corporate-email`,
`income-verification-api`) on Cloud Run through the **Agent Gateway**. IAP
REQUEST_AUTHZ enforces per-tool IAM via Agent Identity, and a Model Armor
CONTENT_AUTHZ extension screens prompts and responses. Tool URLs are
discovered at runtime through the Agent Registry rather than baked into the
agent. End-to-end execution is observable in Cloud Trace.

## Architecture

![Architecture](docs/architecture.png) ##ToDO

## Repository layout

```
agent-gateway/
├── src/
│   ├── corporate-email/             # Python — MCP corporate email service
│   ├── income-verification-api/     # Python — MCP income verification API
│   ├── legacy-dms/                  # Python — MCP legacy document management
│   └── mortgage-agent/              # Python — ADK agent + deploy_agent.py
├── terraform/
│   ├── main.tf, variables.tf, outputs.tf, backend.tf, versions.tf
│   ├── example.tfvars, example.backend.conf
│   └── modules/
│       ├── foundation/              # Project services, APIs, IAM
│       ├── networking/              # VPC, subnets, firewall, PSC
│       ├── agent-engine/            # Agent Runtime infrastructure
│       ├── agent-registry-endpoints/ # Tool registration scripts
│       ├── mcp-cloud-run/           # Cloud Run services + per-svc runtime SAs
│       └── model-armor/             # Model Armor templates + DLP integration
├── cloudrun/                        # Cloud Run service templates (envsubst)
│   ├── corporate-email.yaml.tmpl
│   ├── income-verification-api.yaml.tmpl
│   └── legacy-dms.yaml.tmpl
├── scripts/
│   └── grant_agent_mcp_egress.sh    # Per-MCP IAP egress IAM (run after deploy)
├── skaffold.yaml.tmpl               # Multi-service build + Cloud Run deploy
├── codelab.md                       # Full walkthrough (source of truth)
└── docs/architecture.png   ##ToDO
```

## Prerequisites

- A GCP project with billing enabled.
- Your account must have `roles/owner` or equivalent (`roles/editor` +
  `roles/iam.securityAdmin` + `roles/resourcemanager.projectIamAdmin` +
  `roles/cloudbuild.builds.editor` + `roles/serviceusage.serviceUsageConsumer`).
  - *Note on Cloud Build:* `roles/editor` does not grant permissions to create Cloud Build jobs. If you are not a Project Owner, run:
    ```bash
    export PROJECT_ID=YOUR_PROJECT_ID
    export USER_EMAIL=$(gcloud config get-value account)

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="user:$USER_EMAIL" \
      --role="roles/cloudbuild.builds.editor"

    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="user:$USER_EMAIL" \
      --role="roles/serviceusage.serviceUsageConsumer"
    ```
    *(Alternatively, add your account to `platform_admin_members = ["user:you@example.com"]` in `terraform.tfvars`, and Terraform will manage these grants automatically.)*
- Tools: `gcloud` (authenticated), `terraform >= 1.5`, `uv` (Python package manager).
- The project must be under a GCP **organization** (required for Agent Identity
  IAM principal sets).
- **Bootstrap APIs:** In a new GCP project, the Cloud Resource Manager and Service Usage APIs must be enabled via `gcloud` before Terraform can read project metadata or manage services.

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

---

## Deploy Walkthrough

### Step 0 — Clone and navigate

```bash
cd cloud-networking-solutions/demos/agent-gateway-egress-swp/terraform
```

### Step 1 — Enable Bootstrap APIs

In a new project, enable the foundational APIs required by Terraform and Cloud Storage:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION=us-central1

gcloud services enable \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  dns.googleapis.com \
  agentregistry.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  networkconnectivity.googleapis.com \
  --project="${PROJECT_ID}"
```

### Step 2 — Create the Terraform state bucket

```bash
gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" \
  --location="${REGION}" \
  --uniform-bucket-level-access
```

### Step 3 — Configure Terraform

```bash
cp example.backend.conf backend.conf
# Edit backend.conf: set bucket = "${PROJECT_ID}-tfstate"

cp example.tfvars terraform.tfvars
# Edit terraform.tfvars:
#   project_id      = "YOUR_PROJECT_ID"
#   organization_id = "YOUR_ORG_NUMERIC_ID"   # gcloud organizations list
#   region          = "us-central1"
```

Get the numeric org ID:
```bash
gcloud organizations list
```

### Step 4 — Phase 1 apply (infrastructure + MCP server)

This creates all networking, SWP, Cloud NAT, the Agent Gateway, and the
bug-tickets-mcp Cloud Run service. The Reasoning Engine is NOT created yet
(`deploy_reasoning_engine` defaults to `false`).

```bash
terraform init -backend-config=backend.conf
terraform plan
terraform apply
```

After apply, note these outputs:
```bash
terraform output nat_static_ip          # The IP the MCP server will see
terraform output bug_tickets_mcp_url    # URL used in deploy_agent.py
terraform output agent_gateway_id       # Used in --agent-gateway flag
```

> **Note:** The configuration to force all traffic to the VPC (`VPC_EGRESS_MODE_ALL_TRAFFIC`) requires an `AgentConnectivityTemplate` resource, which is not yet supported in the Google Terraform provider. The Terraform configuration in `modules/agent-gateway/main.tf` automatically handles creating, binding, unbinding, and deleting this template using `local-exec` provisioners under the hood.

### Step 5 — Build and stage agent artifacts

From the agent source directory, build the artifact bundle and write the
manifest that Terraform will reference in Phase 2.

```bash
cd ../src/software-bug-agent

# Install dependencies (uv will create a venv automatically)
uv sync

# Stage agent artifacts to GCS and write build/agent_artifacts.json
uv run python deploy_agent.py \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --mcp-url="$(cd ../../terraform && terraform output -raw bug_tickets_mcp_url)" \
  --build-only
```

The manifest is written to `../../build/agent_artifacts.json` (relative to this
directory), which is the path `terraform/main.tf` expects by default.

### Step 6 — Phase 2 apply (Reasoning Engine)

```bash
cd ../../terraform

terraform apply -var deploy_reasoning_engine=true
```

This creates the `google_vertex_ai_reasoning_engine` with
`agent_gateway_config.agent_to_anywhere_config.agent_gateway` bound, so ALL
agent egress flows through the VPC → SWP → Cloud NAT path.

```bash
terraform output reasoning_engine_name  # full resource ID
```

---

## Verification

### 1. Confirm the static NAT IP

The reserved external IP is visible in the GCP Console:
**VPC Network > IP addresses > External IP addresses** — look for the address
named `<name_prefix>-nat-ip`.

```bash
terraform output nat_static_ip
```

### 2. Send a test query to the agent

Go to **Vertex AI > Agent Engine** in the GCP Console, select the deployed
Reasoning Engine, and click **Test**. Send a prompt like:

```
List all open P1 bugs assigned to alice@quantumroast.example.
```

The agent will call `list_tickets` via MCPToolset, which makes an HTTP request
from the Reasoning Engine container — through the Agent Gateway, the SWP, and
Cloud NAT — to the Cloud Run MCP server.

### 3. Verify the egress IP in Cloud Run logs

The bug-tickets-mcp Cloud Run service logs every request. Check for calls to `/mcp`:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="bug-tickets-mcp" AND textPayload:"/mcp"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="value(textPayload)"
```

You should see the incoming requests arriving from Cloud NAT. If requests are logged with `200 OK`, the egress path is confirmed end-to-end.

## Cleanup

```bash
# 1. Destroy all Terraform-managed resources (automated teardown)
cd terraform
terraform destroy -var deploy_reasoning_engine=true

# 2. (Optional) Delete the state bucket
gcloud storage rm -r "gs://${PROJECT_ID}-tfstate"
```

## License

[Apache License 2.0](LICENSE)
