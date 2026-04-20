# Terraform Infrastructure

This directory contains the Terraform configuration for the MCP Gateway demo infrastructure on GCP.

## Prerequisites

- Terraform >= 1.12.2
- Google Cloud SDK (`gcloud`) authenticated with appropriate permissions
- A GCP project with billing enabled

## Quick Start

```bash
# Copy example configuration
cp example.tfvars terraform.tfvars
# Edit terraform.tfvars with your project details

# Copy example backend configuration
cp example.backend.conf backend.conf
# Edit backend.conf with your GCS bucket details

# Initialize Terraform
terraform init -backend-config=backend.conf

# Preview changes
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars
```

## Known `gcloud` Exceptions

The project convention is to manage all infrastructure via Terraform. The following exceptions use `gcloud` via `null_resource` local-exec because no native Terraform resource exists:

- **Model Armor MCP Content Security** (`modules/model-armor/main.tf`): Uses `gcloud beta services mcp content-security add` to configure MCP floor settings. There is no Terraform resource for this API as of the current provider version.
