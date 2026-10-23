# Example terraform.tfvars for the agent-gateway-shared-vpc-runtime demo.
# Copy this file to terraform.tfvars and fill in the values below.
# See README.md for a full step-by-step deploy walkthrough.

# Required: Three separate projects
governance_project_id = "your-governance-project-id" # Service project 1: Agent Gateway, Registry, Model Armor, MCP Cloud Run
networking_project_id = "your-networking-project-id" # Host project: Shared VPC, subnets, SWP, Cloud NAT, DNS
runtime_project_id    = "your-runtime-project-id"    # Service project 2: Vertex AI Agent Runtime (Reasoning Engine) & staging
organization_id       = "123456789012"               # Numeric org ID (gcloud organizations list)
region                = "us-central1"

# Naming — short prefix used across all resource names
name_prefix = "agw-3p"

# Shared VPC Networking — CIDR ranges (adjust if these overlap existing ranges)
primary_subnet_cidr       = "10.0.0.0/20"
agent_gateway_subnet_cidr = "10.20.0.0/26" # PSC-I dedicated subnet in Shared VPC (must be /26 or larger)
swp_proxy_subnet_cidr     = "10.30.0.0/24" # SWP proxy-only subnet in Shared VPC

# Platform Admin Members — grants your user Cloud Build, Service Usage, and AI Platform access
platform_admin_members = [
  # "user:you@example.com",
]

# Model Armor configuration (enabled by default in Governance project)
enable_model_armor = true

# Optional: change the Gemini model used by the bug-triage agent
# agent_model             = "gemini-2.5-flash"
# model_endpoint_location = "us-central1"

# Phase 2: set to true after running deploy_agent.py --build-only
# deploy_reasoning_engine = true
