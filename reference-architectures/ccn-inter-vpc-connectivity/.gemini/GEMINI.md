# LLM rules and guidance

## Official Documentation & Module Registries
- Terraform Provider Docs: Whenever you are writing or modifying a `google` or `google-beta` resource, you **MUST** refer to the official provider documentation to verify current arguments, deprecations, and syntax:
  - `https://registry.terraform.io/providers/hashicorp/google/latest/docs`
- Google Cloud Modules: Before generating complex infrastructure from scratch, check if an official Google Cloud Terraform module exists. Always prioritize using or referencing modules from these official namespaces:
  - `https://registry.terraform.io/namespaces/terraform-google-modules`
  - `https://registry.terraform.io/namespaces/GoogleCloudPlatform`
- Verification: Do not hallucinate Terraform arguments or module inputs. If you are unsure about a specific variable type or requirement, actively search the provided URLs to confirm the exact schema before generating the code.

## Terraform Coding Standards
- **Syntax & Formatting**: Write code compatible with standard `terraform fmt` conventions. Group resources logically.
- **Variables**: All variables must be strictly typed (e.g., `type = string`, `type = list(object({ ... }))`) and include a clear, descriptive `description`.
- **Outputs**: Generate an `outputs.tf` file exposing relevant IDs, self-links, and endpoints for cross-module or downstream usage.
- **Resource Targeting**: Use `data` blocks to reference existing infrastructure rather than hardcoding IDs or self-links.

## Lab Lifecycle & Deployment
For describing the lab architecture, checking prerequisites, deploying (`examples/ncc` or `examples/vpc-peering`), verifying VPN/BGP/NCC/peering/firewall status, or tearing down lab resources, load and follow the `deploy-network-lab` skill at `.agents/skills/deploy-network-lab/SKILL.md`.
