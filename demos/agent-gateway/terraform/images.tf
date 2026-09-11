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

# MCP container images — built from src/<source_dir>/Dockerfile by regional
# Cloud Build during `terraform apply`, so a single apply is the whole deploy.
#
# There is no declarative "run one build" resource in the Google provider
# (google_cloudbuild_trigger is for repo-connected CI), so the build is invoked
# with `gcloud builds submit` from a local-exec provisioner. This is the same
# call Skaffold used to make; it just lives inside the graph now.
#
# Images are tagged with a hash of their own source. That makes the image URI
# computable at plan time (local-exec cannot return values), and makes a
# re-apply with unchanged source a genuine no-op.
#
# This is a demo/codelab convenience. A production setup would use a
# repo-connected Cloud Build trigger rather than shelling out from Terraform.

locals {
  # Substrings that disqualify a file from the source hash. Entry-for-entry
  # mirror of src/*/.gcloudignore (which controls what is actually uploaded to
  # Cloud Build): build caches and virtualenvs must not perturb the hash, or
  # the image tag churns on every apply. Anything ignored there but hashed here
  # rebuilds a byte-identical image under a new tag; anything hashed there but
  # ignored here ships a change the tag does not reflect. Keep both in sync.
  #
  # Matching is strcontains, not glob — ".pyc" is the substring form of "*.pyc".
  mcp_source_exclude = [
    ".venv/",
    ".git/",
    ".gitignore",
    "__pycache__/",
    ".pyc",
    ".pyo",
    ".ruff_cache/",
    ".mypy_cache/",
    ".pytest_cache/",
  ]

  mcp_source_dir = {
    for k, v in var.mcp_services : k => "${path.module}/../src/${v.source_dir}"
  }

  mcp_source_files = {
    for k, v in var.mcp_services : k => sort([
      for f in fileset(local.mcp_source_dir[k], "**") : f
      if !anytrue([for p in local.mcp_source_exclude : strcontains(f, p)])
    ])
  }

  # Path is folded into the hash alongside content so a pure rename still
  # produces a new tag.
  mcp_source_hash = {
    for k, v in var.mcp_services : k => substr(sha1(join("", [
      for f in local.mcp_source_files[k] :
      "${f}:${filesha1("${local.mcp_source_dir[k]}/${f}")}"
    ])), 0, 12)
  }

  # A service is built from source unless tfvars pins a prebuilt `image`.
  # Empty string counts as unset: `coalesce` skips "" as well as null, so
  # testing only for null here would leave `image = ""` resolving to a computed
  # tag that no build ever produces.
  mcp_build_from_source = {
    for k, v in var.mcp_services : k => v.image == null || v.image == ""
  }

  # Repo name tracks var.name_prefix, matching
  # google_artifact_registry_repository.registry. The image name is the source
  # directory, which is not always the service key (income-verification lives
  # in src/income-verification-api).
  mcp_image_uri = {
    for k, v in var.mcp_services : k => (
      local.mcp_build_from_source[k]
      ? "${var.region}-docker.pkg.dev/${var.project_id}/${var.name_prefix}-docker/${v.source_dir}:${local.mcp_source_hash[k]}"
      : v.image
    )
  }

  # Assembled here rather than inline in the provisioner heredoc: a multi-line
  # expression inside a heredoc interpolation is not something `terraform fmt`
  # indents correctly.
  mcp_build_command = {
    for k, v in var.mcp_services : k => join(" ", concat(
      [
        "gcloud builds submit ${local.mcp_source_dir[k]}",
        "--tag ${local.mcp_image_uri[k]}",
        "--project ${var.project_id}",
        "--region ${var.region}",
        # The default staging bucket gcloud would pick is multi-region, which
        # regional builds reject. Point it at the regional bucket we create.
        "--gcs-source-staging-dir gs://${google_storage_bucket.cloudbuild.name}/source",
        "--quiet",
      ],
      var.cloudbuild_service_account == null ? [] : [
        "--service-account projects/${var.project_id}/serviceAccounts/${var.cloudbuild_service_account}",
        # Cloud Build rejects any build that names a user-managed service
        # account without also naming a logs destination, so this flag is not
        # optional once --service-account is set.
        "--default-buckets-behavior regional-user-owned-bucket",
      ],
    ))
  }
}

# Does the tag the build would produce already exist in Artifact Registry?
#
# The source hash alone cannot answer this: it describes the source tree, not
# the registry. If the image is deleted out from under us — an AR cleanup
# policy, a manual delete, a destroy that took the repository — the hash is
# unchanged, so no rebuild fires and module.mcp_services deploys a Cloud Run
# revision pointing at a tag that is not there. That failure does not clear on
# re-apply; it needs a manual taint. Folding registry state into the trigger
# makes the rebuild automatic.
#
# `|| true` keeps a missing image (or a missing repository, on the very first
# plan) a normal "false" rather than a plan-time error.
data "external" "mcp_image_present" {
  for_each = { for k, v in var.mcp_services : k => v if local.mcp_build_from_source[k] }

  program = ["bash", "-c", <<-EOT
    found=$(gcloud artifacts docker images describe "${local.mcp_image_uri[each.key]}" \
      --project ${var.project_id} --format='value(image_summary.digest)' 2>/dev/null || true)
    if [ -n "$found" ]; then echo '{"present":"true"}'; else echo '{"present":"false"}'; fi
  EOT
  ]
}

# One build per MCP service. `triggers_replace` (not `input`) is what forces
# the replacement that re-runs the creation-time provisioner, so the build
# fires when the source hash moves or when the image goes missing.
#
# The provisioner re-checks the registry and skips the build when the tag is
# already there. That check is what makes the "missing -> built -> present"
# transition cheap: the apply that builds records `<hash>:false`, and the next
# plan reads `<hash>:true`, which is a diff, so the provisioner runs once more
# and exits in about a second instead of rebuilding. It also means `-replace`
# will not force a rebuild of an image that already exists — delete the tag
# from Artifact Registry (or change the source) to rebuild deliberately.
#
# Services with an explicit `image` in tfvars are skipped entirely — that is the
# escape hatch for pinning a prebuilt image.
resource "terraform_data" "mcp_image" {
  for_each = { for k, v in var.mcp_services : k => v if local.mcp_build_from_source[k] }

  triggers_replace = "${local.mcp_source_hash[each.key]}:${data.external.mcp_image_present[each.key].result.present}"

  provisioner "local-exec" {
    command = <<-EOT
      if gcloud artifacts docker images describe "${local.mcp_image_uri[each.key]}" \
           --project ${var.project_id} >/dev/null 2>&1; then
        echo "${local.mcp_image_uri[each.key]} already in Artifact Registry; skipping build"
        exit 0
      fi
      ${local.mcp_build_command[each.key]}
    EOT
  }

  # The build reads from the bucket and writes to Artifact Registry as the
  # Cloud Build service account. Without these edges the first apply on a fresh
  # project races the IAM grants and fails with a permission error. The
  # time_sleep depends on all three grants and adds a propagation pause on top
  # of the ordering, which the grants alone do not give us.
  depends_on = [
    google_artifact_registry_repository.registry,
    google_storage_bucket.cloudbuild,
    time_sleep.cloudbuild_iam_propagation,
  ]

  lifecycle {
    precondition {
      condition     = length(local.mcp_source_files[each.key]) > 0
      error_message = "No source files found under src/${var.mcp_services[each.key].source_dir} for MCP service '${each.key}'. Check that mcp_services[\"${each.key}\"].source_dir names a real directory under src/."
    }
  }
}
