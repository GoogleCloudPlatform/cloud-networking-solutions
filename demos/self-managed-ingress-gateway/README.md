# Self-Managed Ingress Gateway Demo

This demo showcases the two-tier ingress pattern described in the PDF: a public front door in front of one or more private, agent-specific regional backends using Google Cloud networking primitives.

The Terraform here is intentionally a reference scaffold for the architecture rather than a turnkey production deployment. It demonstrates the core control plane needed to model the design:

- global external front door with host-based routing
- per-agent regional internal load balancer
- private service path between tiers
- identity-aware policy enforcement at the edge
- request rewriting and path handling for agent backends
- optional Model Armor / ext_proc integration points

## Architecture summary

Tier 1:
- Global external Application Load Balancer
- Client TLS termination
- Hostname-based routing to the correct agent
- Shared front door for many agent hostnames

Tier 2:
- One regional internal Application Load Balancer per agent or agent group
- Rewrites the request Host and path for the target Vertex AI / Agent Runtime method
- Enforces per-agent access policy and private-only networking

## Files

- `terraform/main.tf` — main showcase infrastructure
- `terraform/variables.tf` — input values and defaults
- `terraform/outputs.tf` — useful endpoints and hostnames
- `terraform/example.tfvars` — sample values

## Usage

```bash
cd demos/self-managed-ingress-gateway/terraform
cp example.tfvars terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Notes

- Replace the sample hostnames and project values with your real domain and GCP project.
- In production, the PSC and ext_proc / Model Armor path would be wired to the specific service attachment and runtime endpoints for your environment.
- This scaffold is structured to spotlight the reference architecture described in the PDF without forcing the entire end-to-end deployment into a single, brittle setup.
