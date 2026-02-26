# Storage Module

This module manages storage resources for the AI Gateway infrastructure, including GCS buckets, Secret Manager, and Artifact Registry.

## Features

- **GCS Bucket:** Store ML models with versioning and lifecycle management.
- **Secret Manager:** Optionally store HuggingFace tokens for private model access.
- **Artifact Registry:** Host Docker images for model inference containers in a dedicated repository.

---

## Resources Created

### GCS Bucket
- Storage bucket for ML models.
- Versioning enabled by default to prevent accidental data loss.
- Lifecycle rules automatically delete old object versions after a configurable period (default: 90 days) while keeping a configurable number of recent versions (default: 3). Both thresholds are controlled via `bucket_lifecycle_age` and `bucket_lifecycle_num_versions`.
- IAM bindings for GKE Workload Identity and compute service accounts.

### Secret Manager (Optional)
- Secret for the HuggingFace API token.
- IAM binding for GKE Workload Identity access.
- Only created if you provide a `huggingface_token`.

### Artifact Registry
- Docker repository for container images.
- Standard format with support for immutable tags.

---

## Usage Guide

### Basic Usage

```hcl
module "storage" {
  source = "./modules/storage"

  project_id     = "YOUR_PROJECT_ID"
  project_number = "YOUR_PROJECT_NUMBER"
  region         = "YOUR_REGION"
}
```

### With HuggingFace Token

```hcl
module "storage" {
  source = "./modules/storage"

  project_id     = "YOUR_PROJECT_ID"
  project_number = "YOUR_PROJECT_NUMBER"
  region         = "YOUR_REGION"

  # Optional: HuggingFace token for private model downloads
  huggingface_token = var.huggingface_token
}
```

---

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_id` | The Google Cloud project ID. | `string` | - | Yes |
| `project_number` | The Google Cloud project number. | `string` | - | Yes |
| `region` | The region for resource deployment. | `string` | - | Yes |
| `labels` | Labels to apply to all resources. | `map(string)` | `{}` | No |
| `bucket_force_destroy` | Allow deletion of bucket even if it contains objects. | `bool` | `true` | No |
| `bucket_storage_class` | Storage class for the bucket (`STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE`). | `string` | `"STANDARD"` | No |
| `bucket_versioning` | Enable versioning for the bucket. | `bool` | `true` | No |
| `bucket_lifecycle_age` | Age in days before deleting old object versions. | `number` | `90` | No |
| `bucket_lifecycle_num_versions` | Number of newer versions to keep before lifecycle deletion. | `number` | `3` | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the model storage bucket. |
| `bucket_url` | URL of the model storage bucket. |
| `huggingface_secret_name` | Full resource name of the HuggingFace secret. |
| `artifact_registry_repository_url` | Full URL for pushing and pulling Docker images. |

---

## IAM Permissions

### GCS Bucket
- `roles/storage.objectViewer` assigned to the GKE Workload Identity and compute service account.
- `roles/storage.objectCreator` assigned to the compute service account.

### Secret Manager
- `roles/secretmanager.secretAccessor` assigned to the GKE Workload Identity.

---

## Examples: Accessing Resources from GKE

### Accessing the GCS Bucket
You can use the Google Cloud SDK within your pods to interact with the storage bucket:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: model-downloader
spec:
  serviceAccountName: default
  containers:
  - name: downloader
    image: google/cloud-sdk:slim
    command:
      - gsutil
      - cp
      - gs://YOUR_BUCKET_NAME/model.bin
      - /tmp/model.bin
```

### Pushing to Artifact Registry
Use the following commands to authenticate and push your images:

```bash
# Authenticate Docker
gcloud auth configure-docker YOUR_REGION-docker.pkg.dev

# Tag and push your image
docker tag my-image:latest YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/images/my-image:latest
docker push YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/images/my-image:latest
```

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
