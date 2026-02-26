# Copyright 2025 Duncan James
# SPDX-License-Identifier: Apache-2.0

/**
 * Apigee Extension Proxy Module
 *
 * Deploys a semantic cache proxy designed for use with GKE Gateway
 * Service Extensions. This proxy has no TargetEndpoint and returns
 * control to the ALB after processing.
 *
 * Key features:
 * - Semantic cache lookup via Vertex AI vector search
 * - Dynamic policy generation from Vertex AI module outputs
 * - No target endpoint (returns control to Gateway)
 * - Deployed with service account for Vertex AI access
 */

# ==============================================================================
# LOCALS - Template rendering configuration
# ==============================================================================

locals {
  # Staging directory for rendered bundle
  staging_dir = "${path.module}/staging/${var.proxy_name}"

  # Template variables for policy rendering
  template_vars = {
    project_number         = var.project_number
    region                 = var.region
    public_endpoint_domain = var.vertex_ai.public_endpoint_domain
    endpoint_numeric_id    = var.vertex_ai.endpoint_numeric_id
    index_numeric_id       = var.vertex_ai.index_numeric_id
    deployed_index_id      = var.vertex_ai.deployed_index_id
    embedding_model        = var.vertex_ai.embedding_model
    similarity_threshold   = var.vertex_ai.similarity_threshold
    ttl_seconds            = var.vertex_ai.ttl_seconds
  }

  # Rendered policy content
  scl_policy_content = templatefile(
    "${path.module}/templates/policies/SCL-Semantic-Cache-Lookup.xml.tftpl",
    local.template_vars
  )

  scp_policy_content = templatefile(
    "${path.module}/templates/policies/SCP-Semantic-Cache-Populate.xml.tftpl",
    local.template_vars
  )
}

# ==============================================================================
# STAGING DIRECTORY STRUCTURE
# ==============================================================================

# Create staging directory structure
resource "null_resource" "create_staging_dirs" {
  triggers = {
    # Recreate if any template variables change
    template_hash = md5(jsonencode(local.template_vars))
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p "${local.staging_dir}/apiproxy/policies"
      mkdir -p "${local.staging_dir}/apiproxy/proxies"
    EOT
  }
}

# ==============================================================================
# RENDERED POLICY FILES
# ==============================================================================

# Semantic Cache Lookup policy (dynamically generated)
resource "local_file" "scl_policy" {
  content  = local.scl_policy_content
  filename = "${local.staging_dir}/apiproxy/policies/SCL-Semantic-Cache-Lookup.xml"

  depends_on = [null_resource.create_staging_dirs]
}

# Semantic Cache Populate policy (dynamically generated)
resource "local_file" "scp_policy" {
  content  = local.scp_policy_content
  filename = "${local.staging_dir}/apiproxy/policies/SCP-Semantic-Cache-Populate.xml"

  depends_on = [null_resource.create_staging_dirs]
}

# ==============================================================================
# STATIC FILES (copied from bundle-extension)
# ==============================================================================

# Copy static policy files
resource "local_file" "am_set_cache_headers" {
  source   = "${path.module}/bundle-extension/apiproxy/policies/AM-Set-Cache-Headers.xml"
  filename = "${local.staging_dir}/apiproxy/policies/AM-Set-Cache-Headers.xml"

  depends_on = [null_resource.create_staging_dirs]
}

resource "local_file" "ev_extract_body_debug" {
  source   = "${path.module}/bundle-extension/apiproxy/policies/EV-Extract-Body-Debug.xml"
  filename = "${local.staging_dir}/apiproxy/policies/EV-Extract-Body-Debug.xml"

  depends_on = [null_resource.create_staging_dirs]
}

resource "local_file" "rf_return_cached_response" {
  source   = "${path.module}/bundle-extension/apiproxy/policies/RF-Return-Cached-Response.xml"
  filename = "${local.staging_dir}/apiproxy/policies/RF-Return-Cached-Response.xml"

  depends_on = [null_resource.create_staging_dirs]
}

# Copy proxy definition
resource "local_file" "proxy_default" {
  source   = "${path.module}/bundle-extension/apiproxy/proxies/default.xml"
  filename = "${local.staging_dir}/apiproxy/proxies/default.xml"

  depends_on = [null_resource.create_staging_dirs]
}

# Copy main proxy descriptor
resource "local_file" "proxy_descriptor" {
  source   = "${path.module}/bundle-extension/apiproxy/cache-extension.xml"
  filename = "${local.staging_dir}/apiproxy/cache-extension.xml"

  depends_on = [null_resource.create_staging_dirs]
}

# ==============================================================================
# PROXY BUNDLE ARCHIVE
# ==============================================================================

# Create the API proxy bundle as a zip file from the staging directory
data "archive_file" "extension_proxy_bundle" {
  type        = "zip"
  output_path = "${path.module}/staging/${var.proxy_name}_extension_proxy_bundle.zip"
  source_dir  = local.staging_dir

  depends_on = [
    local_file.scl_policy,
    local_file.scp_policy,
    local_file.am_set_cache_headers,
    local_file.ev_extract_body_debug,
    local_file.rf_return_cached_response,
    local_file.proxy_default,
    local_file.proxy_descriptor
  ]
}

# ==============================================================================
# APIGEE API PROXY
# ==============================================================================

# Create the Apigee API proxy for extension use
resource "google_apigee_api" "extension_proxy" {
  name           = var.proxy_name
  org_id         = var.apigee_organization
  config_bundle  = data.archive_file.extension_proxy_bundle.output_path
  detect_md5hash = data.archive_file.extension_proxy_bundle.output_md5
}

# Deploy the extension API proxy to the specified environment
resource "null_resource" "extension_proxy_deployment" {
  triggers = {
    proxy_revision = google_apigee_api.extension_proxy.latest_revision_id
    environment    = var.apigee_environment
    organization   = var.apigee_organization
    proxy_name     = var.proxy_name
    bundle_hash    = data.archive_file.extension_proxy_bundle.output_md5
  }

  provisioner "local-exec" {
    command = <<-EOT
      curl -X POST \
        "https://apigee.googleapis.com/v1/organizations/${var.apigee_organization}/environments/${var.apigee_environment}/apis/${var.proxy_name}/revisions/${google_apigee_api.extension_proxy.latest_revision_id}/deployments?override=true" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{
          "serviceAccount": "apigee-proxy-runtime@${var.project_id}.iam.gserviceaccount.com"
        }'
    EOT
  }

  # Ensure the proxy is undeployed before deletion
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Fetch all deployments for this proxy in this environment and undeploy them
      # We use a loop or ignore error because multiple revisions might be deployed
      curl -X DELETE \
        "https://apigee.googleapis.com/v1/organizations/${self.triggers.organization}/environments/${self.triggers.environment}/apis/${self.triggers.proxy_name}/revisions/${self.triggers.proxy_revision}/deployments" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" || true
    EOT
  }

  depends_on = [google_apigee_api.extension_proxy]
}
