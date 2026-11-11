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

# ----------------------------------------------------
# Organization-Scoped Firewall Secure Tag: quarantine
# ----------------------------------------------------
resource "google_tags_tag_key" "fw_quarantine" {
  parent      = "organizations/${var.organization_id}"
  short_name  = "${var.prefix}-quarantine"
  description = "Firewall quarantine tag key for ${var.prefix} network lab"
  purpose     = "GCE_FIREWALL"
  purpose_data = {
    organization = "auto"
  }
}

resource "google_tags_tag_value" "fw_quarantine_true" {
  parent      = google_tags_tag_key.fw_quarantine.id
  short_name  = "quarantine"
  description = "Quarantine compute resource (deny all ingress and egress)"
}

# ----------------------------------------------------
# Organization-Scoped Firewall Secure Tags: Workloads
# (Uses organization = "auto" so tags can be referenced
#  across VPC firewall policies, e.g., app1/app2 in on-prem)
# ----------------------------------------------------
locals {
  workload_secure_tags = toset([
    "on-prem-webserver",
    "on-prem-client",
    "app1-webserver",
    "app1-client",
    "app2-webserver",
    "app2-client",
    "app3-webserver",
    "app3-client",
  ])
}

resource "google_tags_tag_key" "fw_workload" {
  parent      = "organizations/${var.organization_id}"
  short_name  = "${var.prefix}-workload"
  description = "Firewall workload role tag key for ${var.prefix} network lab"
  purpose     = "GCE_FIREWALL"
  purpose_data = {
    organization = "auto"
  }
}

resource "google_tags_tag_value" "fw_workload" {
  for_each = local.workload_secure_tags

  parent      = google_tags_tag_key.fw_workload.id
  short_name  = each.value
  description = "Firewall secure tag for ${each.value}"
}

locals {
  # Standard GCP & RFC1918 ranges
  iap_cidrs       = ["35.235.240.0/20"]
  lb_proxy_cidrs  = ["35.191.0.0/16", "130.211.0.0/22"]
  nlb_proxy_cidrs = ["35.191.0.0/16", "209.85.152.0/22", "209.85.204.0/22"]
  rfc1918_cidrs   = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  # Dynamically included when any CGN or PUPI flag is enabled
  cgn_cidrs = (
    var.enable_on_prem_cgn || var.enable_prod_app1_cgn || var.enable_prod_app2_cgn
  ) ? ["100.64.0.0/10"] : []

  pupi_cidrs = distinct(concat(
    var.enable_on_prem_pupi ? [for s in var.on_prem_pupi_subnets : s.subnet_ip] : [],
    var.enable_prod_app1_pupi ? [for s in var.prod_app1_pupi_subnets : s.subnet_ip] : [],
    var.enable_prod_app2_pupi ? [for s in var.prod_app2_pupi_subnets : s.subnet_ip] : []
  ))

  # Combined internal lab CIDRs (RFC1918 + active CGN + active PUPI)
  internal_lab_cidrs = concat(local.rfc1918_cidrs, local.cgn_cidrs, local.pupi_cidrs)

  # Dynamic proxy-only and PSC NAT subnet CIDRs for prod_transit
  transit_proxy_cidrs = [
    for s in var.prod_transit_vpc_subnets : s.subnet_ip
    if lookup(s, "purpose", null) == "REGIONAL_MANAGED_PROXY"
  ]
  transit_psc_nat_cidrs = [
    for s in var.prod_transit_vpc_subnets : s.subnet_ip
    if lookup(s, "purpose", null) == "PRIVATE_SERVICE_CONNECT"
  ]

  # Dynamic proxy-only subnet CIDRs for prod_app2
  app2_proxy_cidrs = [
    for s in var.prod_app2_base_subnets : s.subnet_ip
    if lookup(s, "purpose", null) == "REGIONAL_MANAGED_PROXY"
  ]

  # Dynamic CIDRs for prod_app3 mesh isolation (only allow intra-VPC app3 and on-prem CIDRs)
  app3_and_on_prem_cidrs = distinct(concat(
    [for s in var.prod_app3_base_subnets : s.subnet_ip],
    [for s in local.on_prem_subnets : s.subnet_ip]
  ))

  # Geo-location & Threat Intelligence lists for Hierarchical FW rules 3100-3400
  embargoed_region_codes    = ["CU", "IR", "KP", "SY"]
  threat_intelligence_lists = ["iplist-known-malicious-ips", "iplist-tor-exit-nodes"]

  # ----------------------------------------------------
  # Hierarchical Firewall Policy Rules
  # ----------------------------------------------------
  hierarchical_fw_rules = {
    500 = {
      direction          = "INGRESS"
      action             = "deny"
      description        = "Deny all ingress to a compute resource that has been assigned a secure tag of 'quarantine'."
      target_secure_tags = [google_tags_tag_value.fw_quarantine_true.id]
      src_ip_ranges      = ["0.0.0.0/0"]
      layer4_configs     = [{ ip_protocol = "all", ports = [] }]
    }
    501 = {
      direction          = "EGRESS"
      action             = "deny"
      description        = "Deny all egress from a compute resource that has been assigned a secure tag of 'quarantine'."
      target_secure_tags = [google_tags_tag_value.fw_quarantine_true.id]
      dest_ip_ranges     = ["0.0.0.0/0"]
      layer4_configs     = [{ ip_protocol = "all", ports = [] }]
    }
    1000 = {
      direction      = "INGRESS"
      action         = "allow"
      description    = "Allow ingress from load balancer proxy IPs."
      src_ip_ranges  = local.lb_proxy_cidrs
      layer4_configs = [{ ip_protocol = "all", ports = [] }]
    }
    2000 = {
      direction      = "INGRESS"
      action         = "allow"
      description    = "Allow ingress from regional external passthrough network load balancer proxy IPs."
      src_ip_ranges  = local.nlb_proxy_cidrs
      layer4_configs = [{ ip_protocol = "all", ports = [] }]
    }
    3000 = {
      direction      = "INGRESS"
      action         = "allow"
      description    = "Allow ingress from Identity-Aware Proxy (IAP)"
      src_ip_ranges  = local.iap_cidrs
      layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
    }
    3100 = {
      direction        = "INGRESS"
      action           = "deny"
      description      = "Deny requests from specific Geo-locations (embargoed countries, etc)"
      src_region_codes = local.embargoed_region_codes
      layer4_configs   = [{ ip_protocol = "all", ports = [] }]
    }
    3200 = {
      direction                = "INGRESS"
      action                   = "deny"
      description              = "Deny requests from known malicious IPs (TOR exit nodes, etc)"
      src_threat_intelligences = local.threat_intelligence_lists
      layer4_configs           = [{ ip_protocol = "all", ports = [] }]
    }
    3300 = {
      direction         = "EGRESS"
      action            = "deny"
      description       = "Deny requests to specific geo-locations (embargoed countries, etc)"
      dest_region_codes = local.embargoed_region_codes
      layer4_configs    = [{ ip_protocol = "all", ports = [] }]
    }
    3400 = {
      direction                 = "EGRESS"
      action                    = "deny"
      description               = "Deny requests to known malicious IPs, TOR exit nodes, etc."
      dest_threat_intelligences = local.threat_intelligence_lists
      layer4_configs            = [{ ip_protocol = "all", ports = [] }]
    }
  }

  # ----------------------------------------------------
  # Per-VPC Global Network Firewall Policy Rules
  # ----------------------------------------------------
  vpc_fw_rules = {
    on_prem = {
      5000 = {
        direction   = "INGRESS"
        action      = "allow"
        description = "Allow ingress to webserver from source secure tag of on-prem, app1, app2, and app3 clients"
        target_secure_tags = [
          google_tags_tag_value.fw_workload["on-prem-webserver"].id,
        ]
        src_secure_tags = [
          google_tags_tag_value.fw_workload["on-prem-client"].id,
          google_tags_tag_value.fw_workload["app1-client"].id,
          google_tags_tag_value.fw_workload["app2-client"].id,
          google_tags_tag_value.fw_workload["app3-client"].id,
        ]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
    }
    prod_transit = {
      10000 = {
        direction      = "INGRESS"
        action         = "allow"
        description    = "Allow ingress from proxy-only subnets. This is used for specific load balancers, and the Secure Web Proxy."
        src_ip_ranges  = local.transit_proxy_cidrs
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      20000 = {
        direction      = "INGRESS"
        action         = "allow"
        description    = "Allow ingress from psc-nat subnets."
        src_ip_ranges  = local.transit_psc_nat_cidrs
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      2000000000 = {
        direction      = "INGRESS"
        action         = "deny"
        enable_logging = true
        description    = "Explicit DENY Ingress rule for logging. The implicit DENY does not log. Create this rule to get logs for denied flows."
        src_ip_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
    }
    prod_services = {}
    prod_app1 = {
      30000 = {
        direction   = "INGRESS"
        action      = "allow"
        description = "Allows ingress to webserver from source secure tag of on-prem, app1, and app2 clients"
        target_secure_tags = [
          google_tags_tag_value.fw_workload["app1-webserver"].id,
        ]
        src_secure_tags = [
          google_tags_tag_value.fw_workload["app1-client"].id,
          google_tags_tag_value.fw_workload["app2-client"].id,
          google_tags_tag_value.fw_workload["on-prem-client"].id,
        ]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      2000000000 = {
        direction      = "INGRESS"
        action         = "deny"
        enable_logging = true
        description    = "Explicit deny Ingress rule for logging. The implicit DENY does not log. Create this rule to get logs for denied flows."
        src_ip_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
    }
    prod_app2 = {
      60000 = {
        direction      = "INGRESS"
        action         = "allow"
        description    = "Allow ingress from proxy-only subnets. This is used for specific load balancers, and the Secure Web Proxy."
        src_ip_ranges  = local.app2_proxy_cidrs
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      70000 = {
        direction   = "INGRESS"
        action      = "allow"
        description = "Allows ingress to webserver from source secure tag of on-prem, app1, and app2 clients"
        target_secure_tags = [
          google_tags_tag_value.fw_workload["app2-webserver"].id,
        ]
        src_secure_tags = [
          google_tags_tag_value.fw_workload["app2-client"].id,
          google_tags_tag_value.fw_workload["app1-client"].id,
          google_tags_tag_value.fw_workload["on-prem-client"].id,
        ]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      2000000000 = {
        direction      = "INGRESS"
        action         = "deny"
        enable_logging = true
        description    = "Explicit DENY Ingress rule for logging. The implicit DENY does not log. Create this rule to get logs for denied flows."
        src_ip_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
    }
    prod_app3 = {
      90000 = {
        direction   = "INGRESS"
        action      = "allow"
        description = "Allows ingress to webserver from source secure tag of app3 and on-prem clients"
        target_secure_tags = [
          google_tags_tag_value.fw_workload["app3-webserver"].id,
        ]
        src_secure_tags = [
          google_tags_tag_value.fw_workload["app3-client"].id,
          google_tags_tag_value.fw_workload["on-prem-client"].id,
        ]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      91000 = {
        direction      = "EGRESS"
        action         = "allow"
        description    = "Allow egress within app3 VPC and to on-prem subnets only"
        dest_ip_ranges = local.app3_and_on_prem_cidrs
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      92000 = {
        direction      = "EGRESS"
        action         = "deny"
        enable_logging = true
        description    = "Isolate app3 in NCC mesh: deny egress to all other internal lab VPCs (app1, app2, transit, services)"
        dest_ip_ranges = local.internal_lab_cidrs
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
      2000000000 = {
        direction      = "INGRESS"
        action         = "deny"
        enable_logging = true
        description    = "Explicit DENY Ingress rule for logging. The implicit DENY does not log. Create this rule to get logs for denied flows."
        src_ip_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "all", ports = [] }]
      }
    }
  }

  # Flatten per-VPC rules for google_compute_network_firewall_policy_rule for_each
  flattened_vpc_fw_rules = merge([
    for vpc_key, rules_map in local.vpc_fw_rules : {
      for priority, rule in rules_map : "${vpc_key}-${priority}" => merge(rule, {
        vpc_key    = vpc_key
        project_id = local.vpcs[vpc_key].project_id
        priority   = tonumber(priority)
      })
    }
  ]...)
}

# ----------------------------------------------------
# Hierarchical Firewall Policy (Attached to L1 Folder)
# ----------------------------------------------------
resource "google_compute_firewall_policy" "hierarchical" {
  parent      = local.base_folder_id
  short_name  = "hfwp-${var.prefix}-network-lab"
  description = "Hierarchical firewall policy for ${var.prefix} network lab folder"
}

resource "google_compute_firewall_policy_association" "hierarchical_l1" {
  name              = "assoc-${split("/", local.base_folder_id)[1]}"
  attachment_target = local.base_folder_id
  firewall_policy   = google_compute_firewall_policy.hierarchical.id
}

resource "google_compute_firewall_policy_rule" "hierarchical_rules" {
  for_each = local.hierarchical_fw_rules

  firewall_policy         = google_compute_firewall_policy.hierarchical.id
  priority                = tonumber(each.key)
  direction               = each.value.direction
  action                  = each.value.action
  description             = each.value.description
  enable_logging          = lookup(each.value, "enable_logging", false)
  disabled                = lookup(each.value, "disabled", false)
  target_service_accounts = lookup(each.value, "target_service_accounts", null)
  target_resources        = lookup(each.value, "target_resources", null)

  dynamic "target_secure_tags" {
    for_each = lookup(each.value, "target_secure_tags", [])
    content {
      name = target_secure_tags.value
    }
  }

  match {
    src_ip_ranges             = lookup(each.value, "src_ip_ranges", null)
    dest_ip_ranges            = lookup(each.value, "dest_ip_ranges", null)
    src_region_codes          = lookup(each.value, "src_region_codes", null)
    dest_region_codes         = lookup(each.value, "dest_region_codes", null)
    src_threat_intelligences  = lookup(each.value, "src_threat_intelligences", null)
    dest_threat_intelligences = lookup(each.value, "dest_threat_intelligences", null)
    src_fqdns                 = lookup(each.value, "src_fqdns", null)
    dest_fqdns                = lookup(each.value, "dest_fqdns", null)
    src_address_groups        = lookup(each.value, "src_address_groups", null)
    dest_address_groups       = lookup(each.value, "dest_address_groups", null)

    dynamic "src_secure_tags" {
      for_each = lookup(each.value, "src_secure_tags", [])
      content {
        name = src_secure_tags.value
      }
    }

    dynamic "layer4_configs" {
      for_each = each.value.layer4_configs
      content {
        ip_protocol = layer4_configs.value.ip_protocol
        ports       = length(layer4_configs.value.ports) > 0 ? layer4_configs.value.ports : null
      }
    }
  }
}

# ----------------------------------------------------
# Global Network Firewall Policies (One per VPC)
# ----------------------------------------------------
resource "google_compute_network_firewall_policy" "vpc_policies" {
  for_each = local.vpcs

  name        = "gfwp-${each.value.network_name}"
  project     = each.value.project_id
  description = "Global network firewall policy for ${each.value.description} (${each.value.network_name})"
}

resource "google_compute_network_firewall_policy_association" "vpc_associations" {
  for_each = local.vpcs

  name              = "assoc-${each.value.network_name}"
  project           = each.value.project_id
  attachment_target = module.vpcs[each.key].network_self_link
  firewall_policy   = google_compute_network_firewall_policy.vpc_policies[each.key].name
}

resource "google_compute_network_firewall_policy_rule" "vpc_rules" {
  for_each = local.flattened_vpc_fw_rules

  project                 = each.value.project_id
  firewall_policy         = google_compute_network_firewall_policy.vpc_policies[each.value.vpc_key].name
  priority                = each.value.priority
  rule_name               = lookup(each.value, "rule_name", null)
  direction               = each.value.direction
  action                  = each.value.action
  description             = lookup(each.value, "description", null)
  enable_logging          = lookup(each.value, "enable_logging", false)
  disabled                = lookup(each.value, "disabled", false)
  target_service_accounts = lookup(each.value, "target_service_accounts", null)

  dynamic "target_secure_tags" {
    for_each = lookup(each.value, "target_secure_tags", [])
    content {
      name = target_secure_tags.value
    }
  }

  match {
    src_ip_ranges             = lookup(each.value, "src_ip_ranges", null)
    dest_ip_ranges            = lookup(each.value, "dest_ip_ranges", null)
    src_region_codes          = lookup(each.value, "src_region_codes", null)
    dest_region_codes         = lookup(each.value, "dest_region_codes", null)
    src_threat_intelligences  = lookup(each.value, "src_threat_intelligences", null)
    dest_threat_intelligences = lookup(each.value, "dest_threat_intelligences", null)
    src_fqdns                 = lookup(each.value, "src_fqdns", null)
    dest_fqdns                = lookup(each.value, "dest_fqdns", null)
    src_address_groups        = lookup(each.value, "src_address_groups", null)
    dest_address_groups       = lookup(each.value, "dest_address_groups", null)

    dynamic "src_secure_tags" {
      for_each = lookup(each.value, "src_secure_tags", [])
      content {
        name = src_secure_tags.value
      }
    }

    dynamic "layer4_configs" {
      for_each = each.value.layer4_configs
      content {
        ip_protocol = layer4_configs.value.ip_protocol
        ports       = length(layer4_configs.value.ports) > 0 ? layer4_configs.value.ports : null
      }
    }
  }
}
