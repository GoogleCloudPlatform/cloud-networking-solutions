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

locals {
  # Strip a trailing dot so the URL matches what HTTP clients send in the Host header
  # (var.mcp_internal_dns_domain may be an FQDN like "mcp-server.internal.").
  mcp_internal_dns_domain_trimmed = (
    var.mcp_internal_dns_domain != null
    ? trimsuffix(var.mcp_internal_dns_domain, ".")
    : null
  )

  mcp_registrations = {
    for name, cfg in var.mcp_servers : name => {
      id             = name
      display_name   = coalesce(cfg.display_name, name)
      description    = cfg.description
      tool_spec_path = cfg.tool_spec_path
      # Both URL modes must include the /mcp path: FastMCP mounts the protocol
      # endpoint at /mcp (see src/*/main.py: mcp.http_app(path="/mcp", ...)),
      # and Cloud Run returns 404 for any other path, including /.
      url = (
        var.mcp_url_mode == "internal_lb"
        ? "https://${name}.${local.mcp_internal_dns_domain_trimmed}/mcp"
        : "${var.mcp_service_urls[name]}/mcp"
      )
    }
  }
}

# Cross-variable input validation. Variable `validation` blocks can't reference
# other variables, so we surface the precondition failures via terraform_data.
resource "terraform_data" "mcp_input_check" {
  lifecycle {
    precondition {
      condition = (
        length(var.mcp_servers) == 0 ||
        var.mcp_url_mode != "internal_lb" ||
        var.mcp_internal_dns_domain != null
      )
      error_message = "mcp_internal_dns_domain is required when mcp_url_mode is 'internal_lb' and mcp_servers is non-empty."
    }
    precondition {
      condition = (
        var.mcp_url_mode != "cloud_run" ||
        length(setsubtract(keys(var.mcp_servers), keys(var.mcp_service_urls))) == 0
      )
      error_message = "mcp_service_urls must contain a URL for every key in mcp_servers when mcp_url_mode is 'cloud_run'."
    }
    precondition {
      condition = alltrue([
        for name, cfg in var.mcp_servers :
        cfg.tool_spec_path != null && fileexists(cfg.tool_spec_path)
      ])
      error_message = format(
        "Every MCP server in var.mcp_servers must set tool_spec_path to an existing file. Missing or unreadable: %s",
        join(", ", [
          for name, cfg in var.mcp_servers :
          "${name}=${coalesce(cfg.tool_spec_path, "<unset>")}"
          if cfg.tool_spec_path == null || !fileexists(cfg.tool_spec_path)
        ])
      )
    }
  }
}

resource "null_resource" "register_endpoints" {
  triggers = {
    google_apis     = jsonencode(var.google_apis)
    custom_services = jsonencode(var.custom_services)
    mcp_servers     = jsonencode(local.mcp_registrations)
    project_id      = var.project_id
    location        = var.location
  }

  provisioner "local-exec" {
    command = templatefile("${path.module}/scripts/register_endpoints.sh.tpl", {
      google_apis     = var.google_apis
      custom_services = var.custom_services
      mcp_servers     = local.mcp_registrations
    })

    environment = {
      PROJECT_ID = var.project_id
      LOCATION   = var.location
    }
  }

  depends_on = [terraform_data.mcp_input_check]
}
