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



# =============================================================================
# Agent Identity IAM bindings
# Grants permissions to all Agent Engine agents in this project.
# See: https://docs.cloud.google.com/agent-builder/agent-engine/agent-identity
# =============================================================================

locals {
  agent_identity_principal = "principalSet://agents.global.org-${var.organization_id}.system.id.goog/attribute.platformContainer/aiplatform/projects/${var.project_number}"
}

resource "google_project_iam_member" "agent_identity_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_browser" {
  project = var.project_id
  role    = "roles/browser"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_express_user" {
  project = var.project_id
  role    = "roles/aiplatform.expressUser"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_api_registry_viewer" {
  project = var.project_id
  role    = "roles/cloudapiregistry.viewer"
  member  = local.agent_identity_principal
}

# Required for the agent to call agentregistry.googleapis.com mcpServers.list
# during startup discovery. Without this, list_mcp_servers() returns 403.
resource "google_project_iam_member" "agent_identity_agent_registry_viewer" {
  project = var.project_id
  role    = "roles/agentregistry.viewer"
  member  = local.agent_identity_principal
}

# Required for the Vertex AI service agent to list MCP servers on behalf of the agent
resource "google_project_iam_member" "aiplatform_re_agent_registry_viewer" {
  project = var.project_id
  role    = "roles/agentregistry.viewer"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
}


resource "google_project_iam_member" "agent_identity_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = local.agent_identity_principal
}

resource "google_project_iam_member" "agent_identity_telemetry_writer" {
  project = var.project_id
  role    = "roles/telemetry.writer"
  member  = local.agent_identity_principal
}

# =============================================================================
# Agent MCP invoker service account
# Agents impersonate this SA at runtime to mint OIDC ID tokens for invoking
# MCP Cloud Run services. The agent identity holds `roles/iam.serviceAccountTokenCreator`
# (granted at the project level below). The SA itself is granted
# `roles/run.invoker` on each MCP service in modules/mcp-cloud-run, so Cloud
# Run sees the impersonated SA as the caller (the agent identity is not
# propagated; Cloud Run does not accept agents.global principalSet members
# directly today, May 2026).
# =============================================================================

resource "google_service_account" "agent_mcp_invoker" {
  project      = var.project_id
  account_id   = "agent-mcp-invoker"
  display_name = "Agent MCP invoker SA"
  description  = "OIDC token target for agents calling MCP Cloud Run services. Agent identity has project-level Token Creator allowing impersonation of this and other project SAs."
}

# Project-level Token Creator binding. We use project-level (not per-SA) so
# this can be applied with `roles/resourcemanager.projectIamAdmin` alone — no
# `iam.serviceAccounts.setIamPolicy` required on the terraform principal,
# which keeps the demo bootstrap minimal. Trade-off: the agent identity can
# impersonate any SA in the project, not just `agent-mcp-invoker`. This is
# acceptable for the demo project (which only contains demo SAs); for
# production, scope this to the specific SA via
# `google_service_account_iam_member` (requires `roles/iam.serviceAccountIamAdmin`
# on the apply principal) or with an IAM condition on `resource.name`.
resource "google_project_iam_member" "agent_identity_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = local.agent_identity_principal
}

# =============================================================================
# Demo user IAM bindings
# Grants roles/aiplatform.user to demo users.
# =============================================================================

resource "google_project_iam_member" "demo_user_aiplatform_user" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/aiplatform.user"
  member   = each.value
}

# =============================================================================
# Reasoning engine (mortgage agent)
# Optional declarative deploy of the agent runtime, replacing the imperative
# src/mortgage-agent/deploy_agent.py create path. Uses google-beta because the
# AGENT_TO_ANYWHERE gateway association (agent_gateway_config) is beta-only.
# The env map mirrors deploy_agent.py's deploy_config env_vars, plus the
# terraform-only AGENT_ARTIFACT_HASH described below.
# =============================================================================

locals {
  # Artifacts manifest produced out-of-band by `deploy_agent.py --build-only`
  # (artifact layout + python_version + class_methods). Guarded so the file is
  # only read when actually deploying the engine.
  agent_artifacts = var.deploy_reasoning_engine ? jsondecode(file(var.agent_artifacts_manifest_path)) : null

  # The manifest is deliberately bucket-free, so recompose the artifact URIs
  # here using the same default convention as deploy_agent.py
  # (`gs://<project>-staging`), overridable via var.agent_staging_bucket.
  agent_staging_bucket = coalesce(var.agent_staging_bucket, "gs://${var.project_id}-staging")
  agent_artifact_base  = "${local.agent_staging_bucket}/${try(local.agent_artifacts.gcs_dir, "agent_engine")}"

  # NOTE: GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY is intentionally omitted.
  # It is a platform-reserved env var that the provider filters out on read, so
  # setting it here produces a permanent diff and a failing in-place update
  # ("The Reasoning Engine failed to be updated"). The platform manages it; the
  # agent code doesn't read it. (deploy_agent.py's imperative path still sets it.)
  #
  # AGENT_ARTIFACT_HASH is the one entry with no counterpart in deploy_agent.py.
  # package_spec's URIs are fixed filenames under a fixed directory, so rebuilt
  # agent code lands at byte-identical URIs and leaves nothing for terraform to
  # diff -- apply reports "No changes" and the engine keeps serving the old
  # pickle. Carrying the manifest's artifact fingerprint in the env forces the
  # in-place update, which redeploys the container and re-pulls the pickle.
  # Unset in manifests written before this existed, hence the try().
  agent_env = {
    AGENT_ARTIFACT_HASH                                     = try(local.agent_artifacts.artifact_hash, "unset")
    ADK_ENABLE_MCP_GRACEFUL_ERROR_HANDLING                  = "true"
    GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES = "false"
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT      = "true"
    OTEL_TRACES_SAMPLER                                     = "parentbased_traceidratio"
    OTEL_TRACES_SAMPLER_ARG                                 = "1.0"
    GOOGLE_GENAI_USE_VERTEXAI                               = "True"
    GOOGLE_CLOUD_LOCATION                                   = var.model_endpoint_location
    MODEL_NAME                                              = var.agent_model
    MCP_REGISTRY_PROJECT                                    = var.project_id
    MCP_REGISTRY_LOCATION                                   = var.region
    MCP_INVOKER_SA_EMAIL                                    = google_service_account.agent_mcp_invoker.email
  }
}

# Ordering gate. `depends_on` only accepts static references, so route the
# caller's dependency values through a terraform_data node the engine can point
# at. Creates no cloud resource; it exists purely to carry the edge from the
# endpoint roles/iap.egressor bindings to the engine below.
resource "terraform_data" "engine_gate" {
  count = var.deploy_reasoning_engine ? 1 : 0
  input = var.engine_depends_on
}

resource "google_vertex_ai_reasoning_engine" "mortgage" {
  count           = var.deploy_reasoning_engine ? 1 : 0
  provider        = google-beta
  deletion_policy = "FORCE"

  # Do not create the engine until the agent principalSet can actually egress
  # to the registered endpoints, and all baseline IAM roles are fully applied.
  # Without this, the IAM roles and engine are unordered, so Terraform may
  # boot the container before its permissions propagate, leading to silent
  # Error Code 3 container startup crashes.
  depends_on = [
    terraform_data.engine_gate,
    google_project_iam_member.agent_identity_service_usage,
    google_project_iam_member.agent_identity_browser,
    google_project_iam_member.agent_identity_express_user,
    google_project_iam_member.agent_identity_aiplatform_user,
    google_project_iam_member.agent_identity_api_registry_viewer,
    google_project_iam_member.agent_identity_agent_registry_viewer,
    google_project_iam_member.aiplatform_re_agent_registry_viewer,
    google_project_iam_member.agent_identity_log_writer,
    google_project_iam_member.agent_identity_metric_writer,
    google_project_iam_member.agent_identity_trace_agent,
    google_project_iam_member.agent_identity_telemetry_writer,
    google_project_iam_member.agent_identity_token_creator,
  ]

  project      = var.project_id
  region       = var.region
  display_name = var.agent_display_name
  description  = "Mortgage Assistant Agent"

  spec {
    agent_framework = "google-adk"
    identity_type   = "AGENT_IDENTITY"

    # Serving operation schemas generated by the build step (SDK-derived; 12
    # methods for this ADK app). Required for package_spec to serve traffic.
    class_methods = var.deploy_reasoning_engine ? jsonencode(local.agent_artifacts.class_methods) : null

    package_spec {
      pickle_object_gcs_uri    = try("${local.agent_artifact_base}/${local.agent_artifacts.pickle_filename}", null)
      dependency_files_gcs_uri = try("${local.agent_artifact_base}/${local.agent_artifacts.dependencies_filename}", null)
      requirements_gcs_uri     = try("${local.agent_artifact_base}/${local.agent_artifacts.requirements_filename}", null)
      python_version           = try(local.agent_artifacts.python_version, null)
    }

    deployment_spec {
      min_instances = 2
      resource_limits = {
        cpu    = "4"
        memory = "8Gi"
      }

      agent_gateway_config {
        agent_to_anywhere_config {
          agent_gateway = var.agent_gateway_id
        }
      }

      dynamic "env" {
        for_each = local.agent_env
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !var.deploy_reasoning_engine || (var.agent_gateway_id != null && var.agent_artifacts_manifest_path != null)
      error_message = "deploy_reasoning_engine requires agent_gateway_id and agent_artifacts_manifest_path (build it with: deploy_agent.py --build-only)."
    }
  }
}
