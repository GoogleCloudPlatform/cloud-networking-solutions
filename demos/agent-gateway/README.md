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

![Architecture](docs/architecture.png)

## Deployment modes

You pick one of two paths when configuring Terraform via the
`enable_cloud_run_private_networking` flag:

| Mode | Cloud Run ingress | Agent Registry URLs | Extra requirements |
| --- | --- | --- | --- |
| **Default (public)** | `all` | `*.run.app` | None |
| **Secure (private)** | `internal-and-cloud-load-balancing` | `<svc>.<your-domain>` via internal ALB | A public DNS zone you own + a Google-managed cert |

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
│   ├── images.tf                    # Cloud Build of src/* during apply
│   ├── example.tfvars, example.backend.conf
│   └── modules/
│       ├── foundation/              # Project services, APIs, IAM
│       ├── networking/              # VPC, subnets, firewall, PSC
│       ├── dns/                     # Public + private Cloud DNS zones
│       ├── certificates/            # Certificate Manager (private path)
│       ├── agent-engine/            # Agent Runtime infrastructure
│       ├── agent-gateway/           # Agent Gateway + service extensions
│       ├── agent-registry-endpoints/ # Tool registration scripts
│       ├── mcp-cloud-run/           # Cloud Run services + per-svc runtime SAs
│       ├── mcp-internal-lb/         # Internal ALB + Serverless NEG (private)
│       └── model-armor/             # Model Armor templates + DLP integration
└── docs/architecture.png
```

## Prerequisites

- A Google Cloud project with billing enabled
- `gcloud` (Cloud SDK)
- `terraform` >= 1.5
- Python 3.12+ with [`uv`](https://docs.astral.sh/uv/)
- (Secure path only) A public DNS zone you own, used for the LB cert

`terraform apply` shells out to `gcloud builds submit` for the MCP images, so
`gcloud` must be on `PATH` with working application-default credentials.

## Quick start

The full procedure with explanations lives in the
[codelab](https://codelabs.developers.google.com/cloudnet-agent-gateway).
Condensed:

```bash
export PROJECT_ID="<your-project-id>"
export REGION="us-central1"
# Secure path only:
export DOMAIN_NAME="agw.example.com"

# 1. Bootstrap APIs
gcloud services enable \
  compute.googleapis.com serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com iam.googleapis.com \
  storage.googleapis.com dns.googleapis.com

# 2. Create state bucket and configure backend
gcloud storage buckets create gs://${PROJECT_ID}-tfstate \
  --location=${REGION} --uniform-bucket-level-access
cp terraform/example.backend.conf terraform/backend.conf
# Edit backend.conf

# 3. Configure Terraform variables
cp terraform/example.tfvars terraform/terraform.tfvars
# Edit terraform/terraform.tfvars (see the codelab for the variable reference)

# 4. Deploy infrastructure, and build + deploy the MCP servers.
#    Each src/<source_dir> is built by regional Cloud Build during the apply
#    and tagged with a hash of its source, so re-applying without touching
#    src/ rebuilds nothing. No separate build step.
cd terraform
terraform init -backend-config=backend.conf
terraform plan
terraform apply
cd ..

# 5. Deploy the mortgage agent to Agent Runtime. Two options:
#
# 5a. Terraform-managed (recommended). Terraform owns the reasoning engine
#     (package_spec) AND the per-agent MCP-server egress grants. Because a
#     reasoning engine is deployed from prebuilt artifacts, this is two-phase:
#     step 4 already created the registry/invoker SA/gateway and the MCP
#     servers; now build the artifacts, then flip deploy_reasoning_engine and
#     re-apply.
cd src/mortgage-agent
uv sync
uv run python deploy_agent.py --build-only \
  --project=${PROJECT_ID} --region=${REGION} \
  --mcp-invoker-sa=$(terraform -chdir=../../terraform output -raw agent_mcp_invoker_email) \
  --model-endpoint-location=global
# ^ uploads pickle/deps/requirements to gs://${PROJECT_ID}-staging/agent_engine/
#   and writes build/agent_artifacts.json (artifact layout + class_methods).
#   The manifest is gitignored and bucket-free: terraform reads it from
#   build/agent_artifacts.json by default and rebuilds the gs:// URIs itself,
#   defaulting the bucket to gs://<project_id>-staging. Override with the
#   agent_staging_bucket tfvar (must match --staging-bucket if you set it).
cd ../../terraform
terraform apply -var deploy_reasoning_engine=true   # or set it in your tfvars
cd ..
#
# 5b. Imperative (kept as-is; also the path for Gemini Enterprise --ge-deploy):
cd src/mortgage-agent
uv sync
uv run python deploy_agent.py \
  --project=${PROJECT_ID} --region=${REGION} \
  --enable-agent-identity --agent-name=mortgage-agent \
  --agent-gateway=projects/${PROJECT_ID}/locations/${REGION}/agentGateways/agent-gateway \
  --mcp-invoker-sa=$(terraform -chdir=../../terraform output -raw agent_mcp_invoker_email) \
  --model-endpoint-location=global
cd ../..

# 6. Egress IAM (roles/iap.egressor) is Terraform-managed:
#    - Endpoints (Google-API + custom services): granted to the agent
#      principalSet, applied by `terraform apply` in step 4.
#    - MCP servers (legacy-dms, income-verification, corporate-email): granted
#      to the deployed agent's per-agent identity when option 5a is used
#      (deploy_reasoning_engine=true). corporate-email is restricted to
#      read-only tools via an IAM condition. With option 5b, MCP egress is not
#      Terraform-managed (the agent identity is created outside Terraform).
```

## Test, register, clean up

- **Playground:** open the agent in the Agent Platform console and trigger a
  prompt; verify in Cloud Trace.
- **Gemini Enterprise:** register the agent in your GE app and chat through
  the GE webapp.
- **Cleanup:** `terraform destroy` (after deleting the deployed Reasoning
  Engine first).

Each is covered in the
[codelab](https://codelabs.developers.google.com/cloudnet-agent-gateway),
including troubleshooting (gateway settle time, missing IAM, DNS peering,
image tag conflicts).

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE)
