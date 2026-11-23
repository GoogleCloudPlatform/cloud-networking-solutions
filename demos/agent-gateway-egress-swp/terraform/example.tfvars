# Example terraform.tfvars for the agent-gateway-egress-swp demo.
# Copy this file to terraform.tfvars and fill in the values below.
# See README.md for a full step-by-step deploy walkthrough.

# Required
project_id      = "your-project-id"
organization_id = "123456789012" # numeric org ID (gcloud organizations list)
region          = "us-central1"

# Naming — short prefix used across all resource names
name_prefix = "agw-egress-swp"

# Networking — CIDR ranges (adjust if these overlap existing ranges in your project)
primary_subnet_cidr       = "10.0.0.0/20"
agent_gateway_subnet_cidr = "10.20.0.0/26" # must be /26 or larger (known-issues #19)
swp_proxy_subnet_cidr     = "10.30.0.0/24"

# Platform Admin Members — grants your user Cloud Build, Service Usage, and AI Platform access
platform_admin_members = [
  # "user:you@example.com",
]

# Optional: change the Gemini model used by the bug-triage agent
# agent_model             = "gemini-2.5-flash"
# model_endpoint_location = "global"

# Phase 2: set to true after running deploy_agent.py --build-only
# deploy_reasoning_engine = true
