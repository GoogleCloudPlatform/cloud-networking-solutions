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
# See: https://cloud.google.com/agent-builder/agent-engine/agent-identity
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

resource "google_project_iam_member" "agent_identity_agent_registry_viewer" {
  project = var.project_id
  role    = "roles/agentregistry.viewer"
  member  = local.agent_identity_principal
}

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
# Demo user IAM
# =============================================================================

resource "google_project_iam_member" "demo_user_aiplatform_user" {
  for_each = toset(var.platform_admin_members)
  project  = var.project_id
  role     = "roles/aiplatform.user"
  member   = each.value
}

# =============================================================================
# Reasoning engine (software-bug-agent)
#
# The key CUJ2 mechanism: agent_gateway_config.agent_to_anywhere_config.agent_gateway
# binds ALL of this engine's egress through the Agent Gateway, which PSC-I
# attaches to the customer VPC, where the policy-based routes steer traffic
# through the Secure Web Proxy and out via Cloud NAT with the static IP.
# =============================================================================

locals {
  agent_artifacts      = var.deploy_reasoning_engine ? jsondecode(file(var.agent_artifacts_manifest_path)) : null
  agent_staging_bucket = coalesce(var.agent_staging_bucket, "gs://${var.project_id}-staging")
  agent_artifact_base  = "${local.agent_staging_bucket}/${try(local.agent_artifacts.gcs_dir, "agent_engine")}"

  agent_env = merge(
    {
      AGENT_ARTIFACT_HASH                                     = try(local.agent_artifacts.artifact_hash, "unset")
      ADK_ENABLE_MCP_GRACEFUL_ERROR_HANDLING                  = "true"
      GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES = "false"
      OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT      = "true"
      OTEL_TRACES_SAMPLER                                     = "parentbased_traceidratio"
      OTEL_TRACES_SAMPLER_ARG                                 = "1.0"
      GOOGLE_GENAI_USE_VERTEXAI                               = "True"
      GOOGLE_CLOUD_LOCATION                                   = var.model_endpoint_location
      MODEL_NAME                                              = var.agent_model
      # Telemetry is enabled via the new env-var mechanism instead of the deprecated
      # enable_tracing=True AdkApp parameter. The old parameter triggers a startup
      # call to telemetry.googleapis.com (internal Google endpoint, unreachable from
      # customer VPCs); this env var uses set_up()'s _telemetry_enabled() path, which
      # does not make that health-check call. See deploy_agent.py for details.
      GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY              = "true"
      # Prevent google-genai from auto-enabling mTLS on Private Google Access.
      GOOGLE_API_USE_CLIENT_CERTIFICATE                       = "false"
      GOOGLE_API_USE_MTLS_ENDPOINT                            = "never"
      # Disable gRPC DirectPath (google-c2p / C2P resolver). When running in GCE,
      # gRPC auto-enables DirectPath, which bypasses DNS and provides Google-internal
      # backend addresses (240.0.0.x IPv4, 2607:f8b0::/32 IPv6). These addresses are
      # unreachable from customer VPCs. Setting GRPC_DNS_RESOLVER=native forces gRPC
      # to use standard DNS resolution (via VPC Cloud DNS, due to dnsPeeringConfig),
      # resolving googleapis.com to Private Google Access VIPs which correctly bypass SWP.
      GRPC_DNS_RESOLVER                                       = "native"
      # Force gRPC to only use IPv4 since the customer VPC/PSC-I does not route IPv6,
      # preventing "Network is unreachable" errors during standard Google API resolution.
      GRPC_ENABLE_IPV6                                        = "false"
    },
    var.mcp_server_url != null ? { BUG_TICKETS_MCP_URL = var.mcp_server_url } : {}
  )
}

resource "terraform_data" "engine_gate" {
  count = var.deploy_reasoning_engine ? 1 : 0
  input = var.engine_depends_on
}

resource "google_vertex_ai_reasoning_engine" "bug_triage" {
  count           = var.deploy_reasoning_engine ? 1 : 0
  provider        = google-beta
  deletion_policy = "FORCE"

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
  ]

  project      = var.project_id
  region       = var.region
  display_name = var.agent_display_name
  description  = "Software bug-triage agent — demonstrates public-internet egress via SWP + Cloud NAT with static IP (CUJ2)"

  spec {
    agent_framework = "google-adk"
    identity_type   = "AGENT_IDENTITY"

    class_methods = var.deploy_reasoning_engine ? jsonencode(local.agent_artifacts.class_methods) : null

    package_spec {
      pickle_object_gcs_uri    = try("${local.agent_artifact_base}/${local.agent_artifacts.pickle_filename}", null)
      dependency_files_gcs_uri = try("${local.agent_artifact_base}/${local.agent_artifacts.dependencies_filename}", null)
      requirements_gcs_uri     = try("${local.agent_artifact_base}/${local.agent_artifacts.requirements_filename}", null)
      python_version           = try(local.agent_artifacts.python_version, null)
    }

    deployment_spec {
      min_instances = 1
      resource_limits = {
        cpu    = "2"
        memory = "4Gi"
      }

      # THE CUJ2 MECHANISM: bind all egress to the Agent Gateway so traffic
      # flows through the customer VPC → SWP → Cloud NAT → static IP.
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
      error_message = "deploy_reasoning_engine requires agent_gateway_id and agent_artifacts_manifest_path (build with: deploy_agent.py --build-only)."
    }
  }
}
