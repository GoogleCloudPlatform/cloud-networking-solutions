# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



/**
 * images.tf — Cloud Build from source for MCP container images.
 *
 * For each entry in var.mcp_services that has a source_dir, this file:
 *   1. Computes a content-based hash of the source directory.
 *   2. Derives a deterministic image URI tagged with that hash.
 *   3. Probes Artifact Registry at plan time to check if the tag already exists.
 *   4. Triggers a Cloud Build only when the source hash changed OR the image
 *      tag was deleted (idempotent: re-applying with unchanged source is a no-op).
 *
 * If you prefer to supply a prebuilt image instead, set the `image` field on
 * the service entry in var.mcp_services and omit `source_dir`.
 */

locals {
  mcp_source_exclude = [
    ".venv",
    ".git",
    "__pycache__",
    ".pytest_cache",
    "*.pyc",
    "*.pyo",
    ".mypy_cache",
    ".ruff_cache",
  ]

  # For each service: resolve the source directory and enumerate source files.
  mcp_source_dir = {
    for k, v in var.mcp_services : k => v.source_dir
    if v.source_dir != null
  }

  mcp_source_files = {
    for k, src in local.mcp_source_dir : k => sort([
      for f in fileset(src, "**") : f
      if !anytrue([for pattern in local.mcp_source_exclude : can(regex(pattern, f))])
    ])
  }

  # Content-hash: sha1 of the sorted file list + each file's sha1.
  mcp_source_hash = {
    for k, files in local.mcp_source_files : k =>
    sha1(join("", concat(
      [sha1(join(",", files))],
      [for f in files : sha1(file("${local.mcp_source_dir[k]}/${f}"))]
    )))
  }

  # Build from source unless a prebuilt image pin is set.
  mcp_build_from_source = {
    for k, v in var.mcp_services : k => v.source_dir != null && v.image == null
  }

  # Deterministic image URI: region-docker.pkg.dev/PROJECT/REPO/SERVICE:HASH
  mcp_image_uri = {
    for k, v in var.mcp_services : k =>
    v.image != null ? v.image : "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.registry.repository_id}/${k}:${local.mcp_source_hash[k]}"
    if v.image != null || v.source_dir != null
  }

  mcp_build_command = {
    for k in keys(local.mcp_source_dir) : k =>
    "gcloud builds submit '${local.mcp_source_dir[k]}' --project '${var.project_id}' --tag '${local.mcp_image_uri[k]}' --region '${var.region}' --gcs-source-staging-dir 'gs://${google_storage_bucket.cloudbuild.name}/source'"
  }
}

# Probe Artifact Registry at plan time: if the hash-tagged image already exists,
# skip the Cloud Build. If the image was deleted, triggers a rebuild.
data "external" "mcp_image_present" {
  for_each = local.mcp_source_dir

  program = ["bash", "-c", <<-EOT
    tag="${local.mcp_image_uri[each.key]}"
    if gcloud artifacts docker images describe "$tag" --quiet >/dev/null 2>&1; then
      echo '{"present":"true"}'
    else
      echo '{"present":"false"}'
    fi
  EOT
  ]

  depends_on = [google_artifact_registry_repository.registry]
}

# Build the container image from source via Cloud Build. The triggers_replace
# key combines the source hash and the registry-presence check, so:
#   - A new source hash always triggers a rebuild.
#   - A deleted image tag also triggers a rebuild (present flips to "false").
#   - An unchanged source with an existing tag is a no-op.
resource "terraform_data" "mcp_image" {
  for_each = local.mcp_source_dir

  triggers_replace = "${local.mcp_source_hash[each.key]}:${data.external.mcp_image_present[each.key].result["present"]}"

  provisioner "local-exec" {
    command = local.mcp_build_command[each.key]
  }

  depends_on = [
    google_artifact_registry_repository.registry,
    google_storage_bucket.cloudbuild,
    time_sleep.cloudbuild_iam_propagation,
  ]

  lifecycle {
    precondition {
      condition     = length(local.mcp_source_files[each.key]) > 0
      error_message = "No source files found in '${local.mcp_source_dir[each.key]}'. Check that the path is correct relative to the terraform/ directory."
    }
  }
}
