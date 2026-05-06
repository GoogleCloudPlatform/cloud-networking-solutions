---
id: getting-started-with-agent-gateway
summary: Deploy a governed multi-tool ADK agent on Agent Runtime that calls MCP servers on Cloud Run through Agent Gateway.
authors: James Duncan
keywords: category:Cloud,docType:Codelab, product:AgentGateway, product:AgentPlatform, product:AgentRuntime, product: CloudRun
layout: paginated

---
# Governing agentic workloads with Agent Gateway on Gemini Enterprise Agent Platform

## Introduction

Duration: 05:00

**Gemini Enterprise Agent Platform** is an open platform for building, scaling, governing, and optimizing enterprise-grade AI agents grounded in your data.

**Agent Runtime** provides the managed execution environment for running agents, such as those built with the open-source **Agent Development Kit (ADK)**, securely within Google Cloud.

This codelab explores how to use these core building blocks to govern an agent initiated by a user in Gemini Enterprise as it securely reaches out to internal tools.

### About Agent Gateway

**[Agent Gateway](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview)** is the networking component of the platform's Agent Governance suite. It acts as the network entry and exit point for all agent interactions, allowing security administrators to enforce centralized governance without requiring developers to manage complex networking primitives.

It facilitates two primary governed access paths:
*   **Client-to-Agent (ingress):** Secures communications between external clients (like Cursor or the Gemini CLI) and your agents.
*   **Agent-to-Anywhere (egress):** Secures communications between agents running on Google Cloud and servers, tools, or APIs running anywhere.

In this codelab, you will focus on the **Agent-to-Anywhere (egress)** mode.

![Access control with Agent Gateway](https://docs.cloud.google.com/static/gemini-enterprise-agent-platform/images/agent-gateway-access-control.png)

To enforce [security policies](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/overview), Agent Gateway integrates tightly with the rest of the ecosystem:
*   **[Agent Registry](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-registry):** A central library of approved agents and tools (including third-party MCP servers).
*   **[Agent Identity](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-identity-overview):** A unique, trackable persona for every agent, secured automatically with end-to-end mTLS.
*   **Identity-Aware Proxy (IAP) & IAM:** The default enforcement layer that validates the agent's identity against fine-grained IAM permissions before allowing calls to specific tools.
*   **[Model Armor](https://docs.cloud.google.com/model-armor/overview):** An AI security guardrail integrated via Service Extensions to sanitize content and protect against prompt injection attacks or data leakage.

### Deployment modes (Public vs. Private networking for Cloud Run)

To make this codelab accessible, you can choose between two networking paths for your internal tools (MCP servers) deployed on Cloud Run:

1.  **Default (Public Ingress):** The MCP servers are deployed to Cloud Run with public hostnames (`ingress=all`). Traffic routes from the agent to the tools via standard `*.run.app` URLs. This requires no custom DNS domains and is the fastest way to learn the governance concepts.
2.  **Secure (Private Networking):** An optional, fully private architecture. The MCP servers are restricted (`ingress=internal-and-cloud-load-balancing`) and exposed via an Internal Application Load Balancer with a Serverless NEG. This requires you to own a public DNS domain to provision a Google-managed certificate.

You will select your preferred path when configuring Terraform.

To learn more about network endpoint ingress for Cloud Run, [please read our docs](https://docs.cloud.google.com/run/docs/securing/ingress).

### What you'll do

- Provision the core infrastructure stack using Terraform
- Build and deploy internal tools as MCP servers on Cloud Run
- Deploy an ADK agent to Agent Runtime using PSC Interface egress
- Configure Agent Gateway service extensions for identity-based access (IAM) and content screening (Model Armor)
- Trace and validate the secure end-to-end execution of the agent

### What you'll need

- A web browser such as [Chrome](https://www.google.com/chrome/)
- A Google Cloud project with billing enabled and **Owner** access
- Organization-level IAM permissions (the codelab grants org-scoped roles)
- A domain you control delegated to Cloud DNS (for the public managed certificate)
- Familiarity with Terraform, `gcloud`, and basic Google Cloud networking

### Codelab topology

![End-to-end architecture: Gemini Enterprise to Agent Runtime to Agent Gateway to MCP servers on Cloud Run](architecture.png)

In this codelab, you will deploy an end-to-end mortgage underwriting agent that securely communicates with three internal tools.

You'll start by provisioning the foundational networking, including a VPC and an internal Application Load Balancer configured as your Agent Gateway. Next, you'll deploy three Model Context Protocol (MCP) servers (`legacy-dms`, `corporate-email`, and `income-verification`) to Cloud Run. These act as your internal proprietary tools.

With the tools in place, you will deploy a `mortgage-agent` built with the ADK to Agent Runtime. You will configure this agent to use a PSC Interface for private egress and enable runtime tool discovery via the Agent Registry.

To secure the flow, you will configure your Agent Gateway with two service extensions. First, a `REQUEST_AUTHZ` extension will verify the Agent Identity against per-tool IAM policies, ensuring the agent only accesses authorized tools. Second, a `CONTENT_AUTHZ` extension using Model Armor will screen the agent's prompts and responses.

Finally, you'll register the agent in Gemini Enterprise, trigger a mortgage-underwriting task as an end user, and verify the secure, governed execution using Cloud Trace.

This codelab is for platform and security engineers of all levels. Expect to spend roughly **90 minutes** completing it.

## Before you begin

Duration: 05:00

### Create a project and authenticate

Create a new GCP project (or reuse one) with billing enabled, then authenticate Cloud Shell or your local machine:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

### Enable bootstrap APIs

Terraform's foundation module enables ~30 APIs on its first apply, but a small bootstrap set is required for `terraform init` and the GCS state bucket:

```bash
gcloud services enable \
  compute.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  dns.googleapis.com
```

### Install required tools

Install the toolchain. On Cloud Shell most of these are already present; on a workstation:

```bash
# uv (Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# skaffold
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64 && \
  sudo install skaffold /usr/local/bin/

# envsubst (gettext) and jq — Cloud Shell already has these
sudo apt-get install -y gettext-base jq
```

You also need **Terraform >= 1.12.2**, **Python 3.12+**, and the **Google Cloud SDK** (`gcloud`).

### Set environment variables

The rest of the codelab assumes these are exported in your shell. Replace <YOUR_PROJECT_ID> with your actual project ID.

> aside positive
> If you are doing the optional secure networking path, define DOMAIN_NAME (e.g., agw.example.com); otherwise, you can ignore it.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export ORG_ID=$(gcloud projects get-ancestors $PROJECT_ID | awk '$2 == "organization" {print $1}')
export REGION="us-central1"

# Only required if using the secure private networking path
export DOMAIN_NAME="agw.example.com"
```

## Clone the repository

Duration: 01:00

```bash
git clone https://github.com/GoogleCloudPlatform/secure-cross-cloud-agents.git
cd secure-cross-cloud-agents/demos/agent-gateway
```

A quick tour of what's in the demo directory:

```
src/                MCP servers (legacy-dms, corporate-email, income-verification-api) + mortgage-agent
terraform/          Root Terraform config + modules (foundation, networking, agent-gateway, model-armor, …)
cloudrun/           Cloud Run service definitions (rendered from .yaml.tmpl via envsubst)
scripts/            grant_agent_mcp_egress.sh — per-MCP IAP egressor binding
skaffold.yaml.tmpl  Skaffold pipeline that builds + deploys all three MCP services to Cloud Run
```

## (Optional) Create a public Cloud DNS zone

Duration: 02:00

> aside positive
> Skip this step if you are using the Default path. If you want to use the simplest setup with public Cloud Run URLs, proceed directly to the next step.

By default for this lab Cloud Run has its [ingress configuration](https://docs.cloud.google.com/run/docs/securing/ingress) set to `all` and the Agent Registry registers each MCP server at its public `*.run.app` URL — no additional DNS, certificates, or load balancer required. If you'd like to switch to private networking (Cloud Run with `ingress = internal-and-cloud-load-balancing` behind an internal Application LB), you also need a public Cloud DNS zone so Certificate Manager can validate the LB cert.

To use the private networking approach:

1. Set `enable_cloud_run_private_networking = true` in `terraform/terraform.tfvars` (along with the secure-path variables shown in the "Configure Terraform variables" section below). The Cloud Run YAML templates pick up the matching `run.googleapis.com/ingress` annotation automatically when you render them with `envsubst` (see "Build and deploy the MCP servers to Cloud Run" below) — there is nothing to hand-edit.
2. Create the public Cloud DNS zone — Certificate Manager validates the regional managed certificate by writing CNAMEs into it:

```bash
gcloud dns managed-zones create agw-example-com \
  --dns-name="${DOMAIN_NAME}." \
  --description="Public zone for ${DOMAIN_NAME}" \
  --visibility=public
```

> aside negative
> Cloud DNS requires names to end with a trailing dot. Carry that convention through `dns_zone_domain`, `mcp_internal_dns_zone.domain`, `psc_interface_dns_zone.domain`, and `agent_gateway_dns_peering_config.domains` in `terraform.tfvars`. The Terraform variables now `validate` for trailing dots at plan time, so a missing one fails fast with a clear message instead of bubbling up as a Cloud DNS API error mid-apply.

The corresponding **private** zone for `mcp.${DOMAIN_NAME}` (used by the MCP internal LB and DNS peering from Agent Runtime) is created automatically by Terraform — you don't need to create it by hand. With private networking off, neither the public nor the private zone is provisioned.

> aside positive
> The MCP internal LB serves TLS for `*.mcp.${DOMAIN_NAME}` using the same Google-managed regional cert. Don't set `mcp_internal_dns_zone.domain` to an unrouteable suffix like `mcp-server.internal.` while `enable_agent_gateway = true` AND `enable_cloud_run_private_networking = true`.
> Agent Gateway does not currently validate the self-signed fallback cert. The Terraform configuration enforces this with a `check` block at plan time (skipped when private networking is off, since there's no LB cert to validate).

> aside positive
> For a deeper walkthrough of the public and private split-horizon DNS pattern this demo uses (managed-zone setup, DNS peering across VPCs, certificate validation flow), see the reference architecture's [DNS setup guide](https://github.com/GoogleCloudPlatform/cloud-networking-solutions/blob/main/reference-architectures/networking-for-ai-inference/docs/dns-setup.md).

## Create the Terraform state bucket and backend config

Duration: 02:00

Create a GCS bucket to hold remote state, then copy the backend template:

```bash
gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
  --location=${REGION} \
  --uniform-bucket-level-access

cp terraform/example.backend.conf terraform/backend.conf
```

Edit `terraform/backend.conf` with your values:

```hcl
bucket = "<your-project-id>-tfstate"
prefix = "agent-gateway"
```

> aside positive
> `terraform/backend.conf` is git-ignored. Each user maintains their own copy.

## Configure Terraform variables

Duration: 05:00

Copy the example tfvars and edit it:

```bash
cp terraform/example.tfvars terraform/terraform.tfvars
```

There are two demo paths, gated by `enable_cloud_run_private_networking`.

### Default path: Cloud Run with public ingress

The simplest setup. MCP services run with `ingress = all` and the Agent Registry registers each one at its literal `*.run.app` URL. No internal LB, no MCP private DNS zone, no Certificate Manager cert, and you don't need to own a DNS zone.

```hcl
# Core
project_id              = "your-project-id"
organization_id         = "123456789012"
platform_admin_members  = ["user:you@example.com"]
region                  = "us-central1"

# Default — false. Cloud Run ingress = all, registry uses *.run.app URLs.
enable_cloud_run_private_networking = false

# MCP services on Cloud Run. The map key becomes the Cloud Run service name.
mcp_services = {
  legacy-dms = {
    image = "us-docker.pkg.dev/cloudrun/container/placeholder"
  }
  corporate-email = {
    image = "us-docker.pkg.dev/cloudrun/container/placeholder"
  }
  income-verification = {
    image = "us-docker.pkg.dev/cloudrun/container/placeholder"
  }
}

# Agent Runtime
enable_agent_engine = true
demo_users          = ["user:you@example.com"]

# Model Armor (AI safety)
enable_model_armor                   = true
enable_model_armor_gemini_enterprise = true
model_armor_admin_members            = ["user:you@example.com"]
model_armor_pi_jailbreak_confidence  = "MEDIUM_AND_ABOVE"
model_armor_sdp_enforcement          = "ENABLED"

# Agent Gateway — works with either path. When private networking is off,
# the gateway intercepts agent egress and routes directly to *.run.app.
enable_agent_gateway          = true
agent_gateway_name            = "agent-gateway"
agent_gateway_subnet_cidr     = "10.20.0.0/28"
agent_gateway_authz_fail_open = true   # Demo only — set false in production to fail-closed

# Agent Registry endpoints — registers Vertex AI, IAP, Discovery Engine, etc.
# in the project's Agent Registry so the agent can discover them at runtime.
enable_agent_registry_endpoints = true
```

### Secure path (optional): internal Application LB

Set `enable_cloud_run_private_networking = true` and add the variables below to provision the full secure stack: internal Application LB at `<service>.<mcp_internal_dns_zone.domain>`, Google-managed cert, Cloud Run with `ingress = internal-and-cloud-load-balancing`, and Agent Gateway DNS peering for `mcp.<domain>.` (auto-prepended). Requires a DNS zone you own.

```hcl
enable_cloud_run_private_networking = true

# DNS — must end with a trailing dot, must match the zone you created
dns_zone_domain            = "agw.example.com."
enable_certificate_manager = true

# mcp_internal_dns_zone.domain MUST be a real subdomain of dns_zone_domain so
# Certificate Manager can issue a Google-managed cert (Agent Gateway does not
# currently validate self-signed certs).
mcp_internal_dns_zone = {
  name   = "mcp-server-internal"
  domain = "mcp.agw.example.com."
}

mcp_lb_protocol = "HTTPS"

# DNS peering for the Agent Gateway. The `mcp.agw.example.com.` entry is
# auto-prepended by the root module — only list extras here (e.g. run.app.
# when enable_run_app_psc = true).
agent_gateway_dns_peering_config = {
  domains        = []
  target_project = "your-project-id"
  target_network = "projects/your-project-id/global/networks/gateway-vpc"
}
```

> aside negative
> The Cloud Run images above point at a Google placeholder. That's intentional — Terraform creates the Cloud Run services with `lifecycle { ignore_changes = [template[0].containers[0].image] }`, so subsequent `skaffold run` invocations replace the image without Terraform fighting them back.

> aside negative
> `agent_gateway_subnet_cidr` must be at least `/28`, RFC 1918, and **must not overlap** `10.0.0.0/24`, `10.0.1.0/24`, or `10.0.2.0/24`. These ranges are reserved for Agent Gateway egress.

## Deploy infrastructure with Terraform

Duration: 20:00

Initialize, review, and apply:

```bash
cd terraform
terraform init -backend-config=backend.conf
terraform plan
terraform apply
```


`terraform apply` provisions ~40 resources on the default path and takes 8–10 minutes on a fresh project (~60 resources / 15–20 minutes when `enable_cloud_run_private_networking = true`). It creates:

- Project foundation (APIs, service identities, quotas)
- VPC, subnets (primary, proxy-only, PSC, PSC-Interface, Agent Gateway co-location), Cloud NAT, firewall rules
- Artifact Registry repo for Cloud Run images
- Three Cloud Run services + per-service runtime SAs (ingress = `all` by default; `internal-and-cloud-load-balancing` when private networking is on)
- Model Armor template + IAM
- Agent Gateway, PSC-I network attachment, IAP and Model Armor extensions, both authorization policies, and the project-level `roles/iap.egressor` grant
- Agent Registry endpoints (Vertex AI, IAP, Discovery Engine, …) plus the three MCP servers (registered at `*.run.app/mcp` by default; at `<svc>.<mcp domain>/mcp` when private networking is on)

Only when `enable_cloud_run_private_networking = true`:
- Internal regional Application LB with serverless NEG (URL-mask routing) + private DNS A records
- MCP private DNS zone (`mcp.<domain>.`) attached to the VPC
- Public DNS zone module (Certificate Manager DNS authorizations) + Regional Google-managed certificate
- PSC Interface DNS zone (orphan when there are no private hostnames to resolve, so it's also gated on the master flag)
- Agent Gateway DNS peering for `mcp.<domain>.` (auto-prepended)

When apply finishes, capture the outputs you'll pipe into the agent deploy:


## Inspect the Agent Registry endpoints

Duration: 03:00

> aside positive
> **Reference only.** The commands in this section have *already been run for you* by Terraform's `agent-registry-endpoints` module. They're shown so you can see exactly what registering an MCP-discoverable endpoint looks like.

The Agent Registry is a per-project catalog of services (Google APIs and your own MCP servers) that an agent discovers at runtime. The mortgage-agent reads it on startup and binds tools dynamically — no MCP URLs are baked into the agent code or its deploy command.

### Endpoints
What Terraform ran on your behalf — for each Google API in `agent_registry_google_apis`, it registered five variants (global, mTLS global, regional, regional mTLS, regional REP). For example, for `aiplatform`:

```bash
gcloud alpha agent-registry services create aiplatform \
  --project=${PROJECT_ID} --location=${REGION} \
  --display-name="Vertex AI Platform" \
  --endpoint-spec-type=no-spec \
  --interfaces="url=https://aiplatform.googleapis.com,protocolBinding=JSONRPC"

gcloud alpha agent-registry services create aiplatform-mtls \
  --project=${PROJECT_ID} --location=${REGION} \
  --display-name="Vertex AI Platform mTLS" \
  --endpoint-spec-type=no-spec \
  --interfaces="url=https://aiplatform.mtls.googleapis.com,protocolBinding=JSONRPC"

gcloud alpha agent-registry services create ${REGION}-aiplatform \
  --project=${PROJECT_ID} --location=${REGION} \
  --display-name="Vertex AI Platform Locational" \
  --endpoint-spec-type=no-spec \
  --interfaces="url=https://${REGION}-aiplatform.googleapis.com,protocolBinding=JSONRPC"

gcloud alpha agent-registry services create aiplatform-${REGION}-rep \
  --project=${PROJECT_ID} --location=${REGION} \
  --display-name="Vertex AI Platform Regional (REP)" \
  --endpoint-spec-type=no-spec \
  --interfaces="url=https://aiplatform.${REGION}.rep.googleapis.com,protocolBinding=JSONRPC"
```
### MCP Servers
The Terraform also registers the 3 MCP Servers for you, to register other MCP servers you can follow the [steps in the documentation](https://docs.cloud.google.com/agent-registry/register-mcp-servers).

```bash
gcloud alpha agent-registry services create legacy-dms \
--project=${PROJECT_ID} \
--location=${REGION} \
--display-name="Legacy DMS" \
--mcp-server-spec-type=tool-spec \
--mcp-server-spec-content=src/legacy-dms/toolspec.json \
--interfaces=url=https://dms.${DOMAIN_NAME}/mcp,protocolBinding=JSONRPC
```

### Verify the registered Endpoints and MCP Servers.

```bash
gcloud alpha agent-registry services list \
  --project=${PROJECT_ID} --location=${REGION} \
  --format="value(displayName,name)"

gcloud alpha agent-registry mcp-servers list \
  --project=${PROJECT_ID} --location=${REGION} \
  --format="value(displayName,name)"
```

Source: `terraform/modules/agent-registry-endpoints/scripts/register_endpoints.sh.tpl`.

## Review the Agent Gateway configuration

Duration: 03:00

> aside positive
> **Reference only.** Terraform has already imported this Agent Gateway. The YAML below is the literal equivalent of `terraform/modules/agent-gateway/main.tf`.

The Agent Gateway is a Google-managed governance plane between Agent Runtime and your tools. In `AGENT_TO_ANYWHERE` mode it's bound to the project's Agent Registry and egresses through a customer-owned PSC Interface so it can reach private MCP servers in your VPC.

If you were importing this gateway by hand, the YAML would look like this:

```yaml
# agent-gateway.yaml — for reference only, Terraform already created this
name: agent-gateway
protocols: [MCP]
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
  - "//agentregistry.googleapis.com/projects/${PROJECT_ID}/locations/${REGION}"
networkConfig:
  egress:
    networkAttachment: projects/${PROJECT_ID}/regions/${REGION}/networkAttachments/agent-gateway-na
  dnsPeeringConfig:
    domains:
      - mcp.${DOMAIN_NAME}.
    targetProject: ${PROJECT_ID}
    targetNetwork: projects/${PROJECT_ID}/global/networks/gateway-vpc
```

```bash
gcloud alpha network-services agent-gateways import agent-gateway \
  --source=agent-gateway.yaml \
  --location=${REGION}
```

Verify the gateway Terraform created:

```bash
gcloud alpha network-services agent-gateways describe agent-gateway \
  --location=${REGION}
```

> aside negative
> The current `terraform-provider-google-beta` does not yet expose `network_config.dns_peering_config`. Terraform applies it via a post-apply `PATCH` on `networkservices.googleapis.com/v1beta1`. You'll see this in `terraform_data.dns_peering` in the module.

## Examine IAP and Model Armor authorization

Duration: 04:00

> aside positive
> **Reference only.** Terraform has already created both extensions and both policies. The commands below come straight from `terraform/modules/agent-gateway/main.tf`.

Agent Gateway delegates authorization to **service extensions**. Two policy profiles cover the demo:

- **REQUEST_AUTHZ** — evaluated once per request at the headers stage. Used here to call **IAP**, which checks whether the calling agent identity has `roles/iap.egressor` on the target MCP server.
- **CONTENT_AUTHZ** — streams body events to the extension for content sanitization. Used here to call **Model Armor**, which screens for prompt injection, jailbreaks, RAI violations, and (optionally) PII via Sensitive Data Protection (SDP).

### IAP REQUEST_AUTHZ extension

```bash
cat > iap-authz-extension.yaml <<EOF
name: agent-gateway-iap-authz
service: iap.googleapis.com
failOpen: true
timeout: 1s
EOF

gcloud beta service-extensions authz-extensions import agent-gateway-iap-authz \
  --source=iap-authz-extension.yaml \
  --location=${REGION} \
  --project=${PROJECT_ID}
```

Bind it to the Agent Gateway with a `REQUEST_AUTHZ` policy:

```bash
curl -fsS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -X POST "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${REGION}/authzPolicies?authz_policy_id=agent-gateway-iap-policy" \
  -d '{
    "name": "agent-gateway-iap-policy",
    "policyProfile": "REQUEST_AUTHZ",
    "action": "CUSTOM",
    "target": {
      "resources": [
        "projects/'"${PROJECT_ID}"'/locations/'"${REGION}"'/agentGateways/agent-gateway"
      ]
    },
    "customProvider": {
      "authzExtension": {
        "resources": [
          "projects/'"${PROJECT_ID}"'/locations/'"${REGION}"'/authzExtensions/agent-gateway-iap-authz"
        ]
      }
    }
  }'
```

### Model Armor CONTENT_AUTHZ extension

The extension's `metadata.model_armor_settings` carries the request and response template IDs Model Armor uses to evaluate each callout:

```bash
cat > ma-extension.yaml <<EOF
name: agent-gateway-ma-authz
service: modelarmor.${REGION}.rep.googleapis.com
failOpen: true
timeout: 1s
metadata:
  model_armor_settings: '[
    {
      "request_template_id":  "projects/${PROJECT_ID}/locations/${REGION}/templates/agw-request-template",
      "response_template_id": "projects/${PROJECT_ID}/locations/${REGION}/templates/agw-response-template"
    }
  ]'
EOF

gcloud beta service-extensions authz-extensions import agent-gateway-ma-authz \
  --source=ma-extension.yaml \
  --location=${REGION} \
  --project=${PROJECT_ID}
```

```bash
curl -fsS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -X POST "https://networksecurity.googleapis.com/v1alpha1/projects/${PROJECT_ID}/locations/${REGION}/authzPolicies?authz_policy_id=agent-gateway-ma-policy" \
  -d '{
    "name": "agent-gateway-ma-policy",
    "policyProfile": "CONTENT_AUTHZ",
    "action": "CUSTOM",
    "target": {
      "resources": [
        "projects/'"${PROJECT_ID}"'/locations/'"${REGION}"'/agentGateways/agent-gateway"
      ]
    },
    "customProvider": {
      "authzExtension": {
        "resources": [
          "projects/'"${PROJECT_ID}"'/locations/'"${REGION}"'/authzExtensions/agent-gateway-ma-authz"
        ]
      }
    }
  }'
```

### Custom DLP templates

Model Armor's `sdpSettings.basicConfig` uses a built-in info-type list — fine for most cases. For finer control (custom info-types, partial masking, surrogate replacement, redaction by likelihood) point Model Armor at your own Cloud DLP **inspect** and **de-identify** templates via `sdpSettings.advancedConfig`.

Create an inspect template that flags US Social Security Numbers at `POSSIBLE` likelihood or above:

```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/inspectTemplates" \
  -d '{
    "templateId": "agw-ssn-inspect-template",
    "inspectTemplate": {
      "displayName": "SSN Inspect Template",
      "inspectConfig": {
        "infoTypes": [
          { "name": "US_SOCIAL_SECURITY_NUMBER" }
        ],
        "minLikelihood": "POSSIBLE"
      }
    }
  }'
```

Create a de-identify template that replaces each finding with its info-type token (e.g. `[US_SOCIAL_SECURITY_NUMBER]`):

```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/deidentifyTemplates" \
  -d '{
    "templateId": "agw-ssn-redaction-template",
    "deidentifyTemplate": {
      "displayName": "SSN Redaction Template",
      "deidentifyConfig": {
        "infoTypeTransformations": {
          "transformations": [{
            "primitiveTransformation": { "replaceWithInfoTypeConfig": {} }
          }]
        }
      }
    }
  }'
```

Then point a Model Armor template's response config at the pair via `sdpSettings.advancedConfig` (this is where Terraform's `model_armor` module would set `advanced_config` if you wired it up):

```json
{
  "filterConfig": {
    "sdpSettings": {
      "advancedConfig": {
        "inspectTemplate":    "projects/${PROJECT_ID}/locations/${REGION}/inspectTemplates/agw-ssn-inspect-template",
        "deidentifyTemplate": "projects/${PROJECT_ID}/locations/${REGION}/deidentifyTemplates/agw-ssn-redaction-template"
      }
    }
  }
}
```

> aside positive
> The Model Armor CONTENT_AUTHZ extension above will automatically pick up these advanced-config templates the next time it evaluates a response — no extension change needed. Make sure the Model Armor service agent (`service-${PROJECT_NUMBER}@gcp-sa-modelarmor.iam.gserviceaccount.com`) holds `roles/dlp.user` and `roles/dlp.reader` on the project (Terraform's `model-armor` module already grants these).

### IAP egressor IAM (per-MCP-server only)

Terraform does **not** create a project-wide `roles/iap.egressor` binding on the implicit IAP agent registry. The binding IAP REQUEST_AUTHZ actually evaluates is per-MCP-server and per-reasoning-engine, granted after the agent is deployed and you know its `reasoningEngines/<id>`. The "Grant the agent per-MCP-server egress" step runs `scripts/grant_agent_mcp_egress.sh` for that.

## Build and deploy the MCP servers to Cloud Run

Duration: 12:00

The `cloudrun/*.yaml.tmpl` and `skaffold.yaml.tmpl` files reference `${PROJECT_ID}`, `${REGION}`, and `${MCP_INGRESS}` (the Cloud Run ingress annotation). Source `MCP_INGRESS` from a Terraform output so the rendered manifests stay in sync with `enable_cloud_run_private_networking`, then render with `envsubst`:

```bash
export MCP_INGRESS=$(cd terraform && terraform output -raw mcp_cloud_run_ingress_annotation)
envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < skaffold.yaml.tmpl > skaffold.yaml
for f in cloudrun/*.yaml.tmpl; do
  envsubst '${PROJECT_ID} ${REGION} ${MCP_INGRESS}' < "$f" > "${f%.tmpl}"
done
```

Each Cloud Run service runs as a per-service runtime SA Terraform created (e.g. `mcp-legacy-dms@${PROJECT_ID}.iam.gserviceaccount.com`). To deploy as those SAs you need `roles/iam.serviceAccountUser` on yourself:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountUser"
```

Build with Cloud Build and deploy with Skaffold:

```bash
skaffold run
```

Skaffold builds three images (`legacy-dms`, `corporate-email`, `income-verification-api`) into your Artifact Registry repo and updates each Cloud Run service to point at the new digest. Verify:

```bash
gcloud run services list --region=${REGION}
```

You should see all three services with `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` and an `ACTIVE` status. They aren't reachable from the public internet, only via the internal LB from inside the VPC (and from the Agent Gateway tenant via PSC-I + DNS peering).

## Deploy the mortgage agent to Agent Runtime

Duration: 06:00

Install the agent's deps and deploy:

```bash
cd src/mortgage-agent
uv sync

uv run python deploy_agent.py \
  --project=${PROJECT_ID} \
  --region=${REGION} \
  --enable-agent-identity \
  --agent-name=mortgage-agent \
  --agent-gateway=projects/${PROJECT_ID}/locations/${REGION}/agentGateways/agent-gateway \
  --model-endpoint-location=global
```

> aside positive
> The agent **discovers MCP tools at runtime** by listing `mcpServers` in the Agent Registry under `projects/${PROJECT_ID}/locations/${REGION}`. The default endpoint is the regional one (`https://${REGION}-agentregistry.googleapis.com/v1alpha`); pass `--registry-endpoint=https://agentregistry.googleapis.com/v1alpha` to use the global endpoint, or `--registry-filter=...` to scope which servers the agent picks up (Google API list-filter syntax).

When the script completes, copy the printed `reasoningEngines/<id>` into your shell:

```bash
export AGENT_ID=<numeric-id-from-output>
cd ../..
```

## Grant the agent per-MCP-server egress

Duration: 02:00

The IAP REQUEST_AUTHZ extension authorizes each tool call by checking the agent's `roles/iap.egressor` on the *specific MCP server* it's calling. There is no project-wide grant — `scripts/grant_agent_mcp_egress.sh` is the only thing that wires up that binding. See [Create an agent-to-MCP server egress policy](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/assign-identity-iam#agent-to-mcp-server).

The script enumerates the MCP servers in the Agent Registry under `projects/${PROJECT_ID}/locations/${REGION}` and merges a `roles/iap.egressor` binding for the agent principal into each server's IAM policy (mirroring `gcloud add-iam-policy-binding` semantics).

### Use case 1 — Unconditional grant scoped to specific MCP servers

```bash
./scripts/grant_agent_mcp_egress.sh \
  --mcp \
  --agent-id ${AGENT_ID} \
  --mcp-filter "legacy-dms income-verification"
```

### Use case 2 — Conditional grant (CEL) scoped to a specific MCP server

To restrict the agent to a subset of tools on a single MCP server, attach an IAM condition. The Agent Gateway publishes per-tool attributes that IAP REQUEST_AUTHZ exposes to CEL including:
  -   `iap.googleapis.com/mcp.toolName`
  -   `iap.googleapis.com/mcp.tool.isReadOnly`
  -   `iap.googleapis.com/request.auth.type`.

Restrict the agent to **read-only tools only** on `corporate-email`:

```bash
./scripts/grant_agent_mcp_egress.sh \
  --mcp \
  --agent-id ${AGENT_ID} \
  --mcp-filter "corporate-email" \
  --condition-expression "api.getAttribute('iap.googleapis.com/mcp.tool.isReadOnly', false) == true" \
  --condition-title "ReadOnlyToolsOnly" \
  --condition-description "Restrict ${AGENT_ID} to read-only tools on corporate-email"
```

After this runs, write tools on `corporate-email` return `403 PermissionDenied` from IAP REQUEST_AUTHZ; read-only tools continue to work.

> aside positive
> The script merges its binding into each resource's existing IAM policy (`gcloud add-iam-policy-binding` semantics). Re-running with the same args is a no-op, prior bindings from colleagues or other tools are preserved.

### Verify the bindings

Navigate to [Policies tab](https://console.cloud.google.com/agent-platform/policies/iam) and you'll see the list of Policies created against the Endpoints and Mcp Servers.

### Additional Use Cases:

### Additional Use case 1: Allow all agents to egress to all endpoints

Optional — useful for demos and dev environments where you want every agent in the project to reach every MCP server and endpoint without per-agent grants. With `--bind-all-agents` the script writes a `roles/iap.egressor` binding for the project-wide Agent Engine principalSet on each MCP server and endpoint, so every reasoning engine in `${PROJECT_ID}` is authorized everywhere:

```bash
./scripts/grant_agent_mcp_egress.sh --bind-all-agents
```

### Additional Use case 2: Unconditional grant on every MCP server, scoped to one agent

Run this after every agent redeploy. With no filter and no condition, the named agent gets `roles/iap.egressor` on every MCP server in the registry:

```bash
./scripts/grant_agent_mcp_egress.sh \
  --mcp \
  --agent-id ${AGENT_ID}
```

## Test the agent in the Agent Platform console

Duration: 05:00

The Agent Platform console ships with a Playground that lets you chat with the deployed agent directly. It's the fastest way to smoke-test tool calls and inspect traces before wiring the agent into Gemini Enterprise.

1. Open the [Agent Platform Deployments](https://console.cloud.google.com/agent-platform/runtimes) page in the Google Cloud console.
2. Use the **Filter** field if you need to narrow the runtime list, then click your `mortgage-agent` runtime.
3. Open the **Playground** tab.
4. Type a prompt to chat with the agent:
```text
I am reviewing the Sterling familys current application. Can you summarize their 2024 and 2025 tax returns and verify if their total household income meets our 2026 debt-to-income requirements?
```
This should return a response from the Document Management tool and Income Verification tool, SSN's should also be redacted in this response.
5. Type a follow up prompt:
```text
Can you send a summary of this to my email jane@example.com
```
The agent should identity it doesn't have access to the send_email tool and response accordingly.

Click **New Session** to start a fresh conversation.

Because the agent was deployed with OpenTelemetry instrumentation, the Playground exposes four side-panel views you can flip between as the agent responds:

- **Trace** — full traces of the conversation, including the Agent Gateway, IAP REQUEST_AUTHZ, and Model Armor CONTENT_AUTHZ spans
- **Event** — a graph of invoked tools and event details for the current turn
- **State** — the agent's session state and tool inputs/outputs
- **Sessions** — every session you've started against this runtime

> aside positive
> The Playground bypasses Gemini Enterprise authentication entirely, which makes it the fastest place to confirm the IAP REQUEST_AUTHZ extension is granting tool calls correctly. If a tool returns 403 here, re-run `scripts/grant_agent_mcp_egress.sh` before debugging deeper.

## Gemini Enterprise Setup & Testing

Duration: 15:00
### Setup Gemini Enterprise
Follow the [getting started with Gemini Enterprise guide](https://docs.cloud.google.com/gemini/enterprise/docs/quickstart-gemini-enterprise).

### Register our ADK Agent with Gemini Enterprise
Follow the steps to register our agent in Gemini Enterprise, you can follow the [steps here](https://docs.cloud.google.com/gemini/enterprise/docs/register-and-manage-an-adk-agent#register-an-adk-agent).

1.  In the Google Cloud console, navigate to the **Gemini Enterprise** page.
2.  Select the Gemini Enterprise App where the agent is registered.
3.  Open the URL shown in the **Your Gemini Enterprise webapp is ready** section.
4.  Select the **Agent** tab from the left menu to open the [Agent Gallery](https://cloud.google.com/gemini/enterprise/docs/agent-gallery).
5.  Select **Mortgage Assistant Agent** and start chatting.

Try the same prompts from the Agent Runtime Playground:

Initial prompt:
```text
I am reviewing the Sterling familys current application. Can you summarize their 2024 and 2025 tax returns and verify if their total household income meets our 2026 debt-to-income requirements?
```
Follow up prompt:
```text
Can you send a summary of this to my email jane@example.com
```

If you navigate back to the Agent Deployment section in the console, select our agent deployment and go to the [traces tab](https://docs.cloud.google.com/gemini-enterprise-agent-platform/optimize/observability/traces), you'll now see the Gemini Assistant agent in the span showing the call originated from Gemini Enterprise.

## Troubleshooting & common fixes

Duration: 02:00

*   **`terraform apply` fails on the Agent Gateway with "resource is being created and therefore can not be updated"** — the gateway's tenant project takes ~30 seconds to settle before authz policies can attach. The module's `time_sleep.wait_for_gateway` handles this; just rerun `terraform apply`.

*   **Agent reports "no MCP servers found" or boots with utility tools only** — confirm `enable_agent_registry_endpoints = true` in `terraform.tfvars`, then:

    ```bash
    gcloud alpha agent-registry mcp-servers list \
      --project=${PROJECT_ID} --location=${REGION}
    ```

    You should see three entries (one per Cloud Run MCP service). If the list is empty, check that the MCP services are reachable from inside the VPC and that the Agent Gateway has populated the registry (it does this lazily on first proxied tool list).

*   **Tool calls return 403 PermissionDenied** — re-run `scripts/grant_agent_mcp_egress.sh`. The most common cause is forgetting to re-grant after redeploying the agent (the `reasoningEngines/<id>` changes each deploy).

*   **`skaffold run` fails with "permission denied on service account"** — you're missing `roles/iam.serviceAccountUser`. Re-run the self-grant in the previous step.

*   **DNS peering errors from Agent Gateway to MCP LB** — check that `agent_gateway_dns_peering_config.target_network` matches `projects/${PROJECT_ID}/global/networks/${VPC_NAME}` exactly, and that every `domains` entry ends with a trailing dot.

*   **`terraform plan` keeps wanting to update Cloud Run image tags** — this should not happen because of the `lifecycle { ignore_changes }` rule. If it does, confirm you didn't edit `mcp_services[*].image` in `terraform.tfvars` after `skaffold run`.

## Clean up

Duration: 10:00

The reasoning engine is *not* managed by Terraform (the ADK SDK creates it). Delete it manually:

```bash
gcloud beta ai reasoning-engines delete ${AGENT_ID} \
  --region=${REGION} --project=${PROJECT_ID}
```

Tear down everything Terraform created:

```bash
cd terraform
terraform destroy
cd ..
```

If you created the public DNS zone just for this codelab:

```bash
gcloud dns managed-zones delete agw-example-com
```

Finally, delete the Terraform state bucket:

```bash
gcloud storage rm -r gs://${PROJECT_ID}-tfstate
```

## Congratulations

Duration: 01:00

Congratulations! You have successfully implemented comprehensive agent governance for a multi-tool ADK agent using Agent Gateway. By acting as the centralized network control plane, Agent Gateway allowed you to establish a secure egress path to private tools, enforce fine-grained identity-based IAM policies via Identity-Aware Proxy, and sanitize content interactions using integrated Model Armor guardrails.

### What you've learned
- How to deploy and configure Agent Gateway as the central governance layer for Agent-to-Anywhere egress traffic.
- How to integrate the Agent Registry for governed, dynamic runtime tool discovery.
- How to write and enforce per-tool and condition-based IAM policies to strictly control agent execution paths.
- How to leverage Agent Gateway service extensions to apply Model Armor policies, automatically intercepting and redacting sensitive agent traffic.

### Reference docs
- [Agent Governance Policies Overview](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/policies/overview)
- [Agent Gateway Documentation](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/gateways/agent-gateway-overview)
- [Agent Identity Documentation](https://docs.cloud.google.com/gemini-enterprise-agent-platform/govern/agent-identity-overview)
- [Gemini Enterprise Agent Platform Overview](https://docs.cloud.google.com/gemini-enterprise-agent-platform/overview)
