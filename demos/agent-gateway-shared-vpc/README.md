# Agent Gateway with Shared VPC (CUJ2 Extension)

This demo extends the **CUJ 2** architecture (Agent Gateway Public Egress via Secure Web Proxy + Cloud NAT Static IP) into a **Two-Project Enterprise Topology** using **Google Cloud Shared VPC**.

In this topology, enterprise responsibilities are strictly decoupled between two separate projects:

1. **Networking Project (Host Project)**:
   - Owns the centralized network infrastructure.
   - Hosts the **Shared VPC** (`google_compute_shared_vpc_host_project`) and associates the Governance project as a service project (`google_compute_shared_vpc_service_project`).
   - Hosts the subnets:
     - Primary workload subnet (`10.0.0.0/20`)
     - Dedicated PSC-I subnet for Agent Gateway (`10.20.0.0/26`, `purpose = "PRIVATE_SERVICE_CONNECT"`)
     - Dedicated proxy-only subnet for Secure Web Proxy (`10.30.0.0/24`, `purpose = "REGIONAL_MANAGED_PROXY"`)
   - Hosts the **Secure Web Proxy (SWP)** in `NEXT_HOP_ROUTING_MODE`, security policies, and Policy-Based Routes (PBRs).
   - Hosts the **Cloud Router** and **Cloud NAT** with a reserved static external IP address.
   - Hosts the **Private Cloud DNS Zone** for `googleapis.com.` (Private Google Access routing).
   - Manages VPC firewall rules.

2. **Governance Project (Service Project)**:
   - Owns the AI agent workload, gateway governance, and application components.
   - Hosts the **Agent Gateway** (`AGENT_TO_ANYWHERE`) and **Agent Connectivity Template** (`deployment_model = "CENTRALIZED"`).
   - Provisions the **PSC-I Network Attachment** in the service project, bound to the Shared VPC subnet in the Host Project.
   - Hosts the **Agent Registry** endpoints and custom services.
   - Hosts **Model Armor** templates (Request/Response guardrails, Prompt Injection / Jailbreak filters, RAI filters, and DLP templates).
   - Hosts the **MCP Cloud Run** service (`bug-tickets-mcp`) and Artifact Registry repository.
   - Hosts the **Vertex AI Reasoning Engine** (`software-bug-agent`).

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│  Governance Project (Service Project: var.governance_project_id)       │
│                                                                        │
│   Vertex AI Agent Engine (Reasoning Engine)                            │
│     │ agent_gateway_config                                             │
│     ▼                                                                  │
│   Agent Gateway (projects/.../agentGateways/agent-gateway)             │
│     │ AgentConnectivityTemplate (CENTRALIZED, ALL_TRAFFIC)             │
│     ▼                                                                  │
│   PSC-I Network Attachment (in Governance Project)                     │
│     │                                                                  │
│     │ (Attached via Shared VPC to Host Subnet)                         │
└─────┼──────────────────────────────────────────────────────────────────┘
      │
      ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Networking Project (Host Project: var.networking_project_id)          │
│                                                                        │
│   Shared VPC Network                                                   │
│   └── Agent Gateway Subnet (10.20.0.0/26, purpose=PSC)                 │
│         │                                                              │
│         ├── PBR 1500: *.googleapis.com Bypass SWP                      │
│         │     → Cloud DNS (googleapis.com. → 199.36.153.8/30)          │
│         │     → Private Google Access (Google APIs)                    │
│         │                                                              │
│         └── PBR 2000: All Other Traffic Redirect to SWP                │
│               │                                                        │
│               ▼                                                        │
│         Secure Web Proxy (NEXT_HOP_ROUTING_MODE)                       │
│           • SWP Proxy-Only Subnet (10.30.0.0/24)                       │
│           • Gateway Security Policy (ALLOW all)                        │
│           • Anti-loop PBR 1000                                         │
│               │                                                        │
│               ▼                                                        │
│         Cloud Router → Cloud NAT (Static External IP)                  │
└───────────────┬────────────────────────────────────────────────────────┘
                │ Egress to Internet (Source IP = Cloud NAT Static IP)
                ▼
┌────────────────────────────────────────────────────────────────────────┐
│  Public Internet / Destination Endpoints                               │
│                                                                        │
│   Governance Project Cloud Run: bug-tickets-mcp (*.run.app)            │
│     (Logs verify inbound caller IP matches Cloud NAT Static IP)        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

1. **Two Google Cloud Projects**:
   - `governance_project_id`: Project for Agent Gateway, Reasoning Engine, Model Armor, and MCP.
   - `networking_project_id`: Project for Shared VPC, subnets, SWP, Cloud NAT, and DNS.
   - The user deploying this demo must have **Owner** or **Editor + Network Admin** permissions on both projects.
2. **Tools Installed**:
   - `gcloud` CLI (authenticated via `gcloud auth login` and `gcloud auth application-default login`)
   - `terraform` (>= 1.12.2)
   - `python` (>= 3.11) with `uv` or `pip`
   - `curl` and `jq`

---

## Deployment Walkthrough

### Step 1: Configuration

In `demos/agent-gateway-shared-vpc/terraform/`:

```bash
cd demos/agent-gateway-shared-vpc/terraform

# Configure backend (optional, or use local state by omitting -backend-config)
cp example.backend.conf backend.conf
# Edit backend.conf with your GCS bucket name

# Configure variables
cp example.tfvars terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
governance_project_id = "my-gov-project"
networking_project_id = "my-net-project"
organization_id       = "123456789012"
platform_admin_members = [
  "user:your-email@example.com"
]
region = "us-central1"
```

### Step 2: Initialize & Apply Phase 1 (Infrastructure, Shared VPC & Gateway)

Initialize Terraform:
```bash
terraform init -backend-config=backend.conf
```

Validate and plan:
```bash
terraform validate
terraform plan
```

Apply Phase 1:
```bash
terraform apply
```

This provisions:
- Foundation APIs on both projects and Shared VPC linkage.
- Cross-project IAM (`roles/compute.networkUser` and `roles/dns.peer` on Host project).
- Shared VPC network, subnets, Cloud NAT with static IP, SWP, and Private DNS in Host project.
- Model Armor templates in Governance project.
- Artifact Registry and `bug-tickets-mcp` Cloud Run service in Governance project.
- PSC-I Network Attachment, Agent Connectivity Template, and Agent Gateway in Governance project.

### Step 3: Package Agent & Deploy Reasoning Engine (Phase 2)

1. Build the agent artifacts manifest:
```bash
cd ../src/software-bug-agent

# Set up environment
cp .env.example .env
# Edit .env with your governance_project_id, region, and bug_tickets_mcp_url from terraform output

# Package the agent
uv run python deploy_agent.py \
  --project="$(cd ../../terraform && terraform output -raw governance_project_id)" \
  --region="us-central1" \
  --build-only
```

2. Deploy the Reasoning Engine via Terraform:
```bash
cd ../../terraform
terraform apply -var="deploy_reasoning_engine=true"
```

---

## Verification & Testing

### 1. Verify Shared VPC & Network Attachment
Confirm that the Network Attachment in the Governance project references the Host project's PSC subnet:
```bash
gcloud compute network-attachments describe \
  $(terraform output -raw network_attachment_id | awk -F/ '{print $NF}') \
  --region=us-central1 \
  --project=$(terraform output -raw governance_project_id)
```

### 2. Verify Agent Gateway & Connectivity Template
```bash
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://networkservices.googleapis.com/v1/projects/$(terraform output -raw governance_project_id)/locations/us-central1/agentGateways/$(terraform output -raw agent_gateway_name)" | jq .
```

### 3. Verify Agent Runtime Egress via SWP & Static IP
Run a test query against the Reasoning Engine:
```bash
python3 -c "
import vertexai
from vertexai.preview import reasoning_engines

vertexai.init(project='$(terraform output -raw governance_project_id)', location='us-central1')
agent = reasoning_engines.ReasoningEngine('$(terraform output -raw reasoning_engine_id)')
response = agent.query(input='List the latest open bug tickets')
print(response)
"
```

Check the Cloud Run logs in the Governance project to confirm the request originated from the Cloud NAT static IP:
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND textPayload:"bug-tickets-mcp"' \
  --project=$(terraform output -raw governance_project_id) \
  --limit=5 \
  --format="value(httpRequest.remoteIp)"
```
The IP should match `terraform output -raw nat_static_ip`.

---

## Clean Up / Destruction

To delete all resources in order:

```bash
cd demos/agent-gateway-shared-vpc/terraform

# Destroy the Reasoning Engine first (or destroy all resources)
terraform destroy
```
