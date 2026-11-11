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

variable "prefix" {
  description = "Prefix for folders and projects."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9]{1,7}$", var.prefix))
    error_message = "prefix must be 1 to 7 lowercase alphanumeric characters so generated project IDs stay within the 30-character GCP limit."
  }
}

# Organization ID, required for creating the service projects
variable "organization_id" {
  description = "The organization ID."
  type        = string

  validation {
    condition     = can(regex("^\\d+$", var.organization_id))
    error_message = "organization_id must be a numeric string (e.g., \"123456789012\")."
  }
}

# Billing account ID, required for creating the service projects
variable "billing_account_id" {
  description = "The ID of the billing account to associate projects with."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}$", var.billing_account_id))
    error_message = "billing_account_id must match the format XXXXXX-XXXXXX-XXXXXX."
  }
}

# CGN and PUPI subnets for on-prem VPC
variable "enable_on_prem_cgn" {
  description = "Enable CGN subnets for on-prem VPC."
  type        = bool
  default     = true
}

variable "enable_on_prem_pupi" {
  description = "Enable PUPI subnets for on-prem VPC."
  type        = bool
  default     = true
}

# CGN and PUPI subnets for App 1 VPC
variable "enable_prod_app1_cgn" {
  description = "Enable CGN subnets for App 1 VPC."
  type        = bool
  default     = true
}

variable "enable_prod_app1_pupi" {
  description = "Enable PUPI subnets for App 1 VPC."
  type        = bool
  default     = true
}

# CGN and PUPI subnets for App 2 VPC
variable "enable_prod_app2_cgn" {
  description = "Enable CGN subnets for App 2 VPC."
  type        = bool
  default     = true
}

variable "enable_prod_app2_pupi" {
  description = "Enable PUPI subnets for App 2 VPC."
  type        = bool
  default     = true
}

# Base subnets for on-prem VPC
variable "on_prem_base_subnets" {
  description = "A list of base subnets for the on-prem VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-onprem-p-use4-client"
      subnet_ip     = "192.168.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-use4-web"
      subnet_ip     = "192.168.1.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-client"
      subnet_ip     = "192.168.2.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-web"
      subnet_ip     = "192.168.3.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.on_prem_base_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in on_prem_base_subnets must be valid IPv4 CIDR blocks."
  }
}

# CGN subnets for on-prem VPC, only created if enable_on_prem_cgn is true
variable "on_prem_cgn_subnets" {
  description = "A list of CGN subnets for the on-prem VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-onprem-p-use4-cgn-client"
      subnet_ip     = "100.64.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-use4-cgn-web"
      subnet_ip     = "100.64.1.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-cgn-client"
      subnet_ip     = "100.64.2.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-cgn-web"
      subnet_ip     = "100.64.3.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.on_prem_cgn_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in on_prem_cgn_subnets must be valid IPv4 CIDR blocks."
  }
}

# PUPI subnets for on-prem VPC, only created if enable_on_prem_pupi is true
variable "on_prem_pupi_subnets" {
  description = "A list of PUPI subnets for the on-prem VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-onprem-p-use4-pupi-client"
      subnet_ip     = "1.2.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-use4-pupi-web"
      subnet_ip     = "1.2.1.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-pupi-client"
      subnet_ip     = "1.2.2.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-onprem-p-usw1-pupi-web"
      subnet_ip     = "1.2.3.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.on_prem_pupi_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in on_prem_pupi_subnets must be valid IPv4 CIDR blocks."
  }
}


# Subnets for production transit VPC
variable "prod_transit_vpc_subnets" {
  description = "A list of subnets for the production transit VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
    purpose       = optional(string)
    role          = optional(string)
  }))
  default = [
    {
      subnet_name   = "snet-transit-p-use4-std"
      subnet_ip     = "10.10.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-transit-p-use4-r-proxy"
      subnet_ip     = "172.16.0.0/24"
      subnet_region = "us-east4"
      purpose       = "REGIONAL_MANAGED_PROXY"
      role          = "ACTIVE"
    },
    {
      subnet_name   = "snet-transit-p-use4-psc-nat"
      subnet_ip     = "172.16.1.0/24"
      subnet_region = "us-east4"
      purpose       = "PRIVATE_SERVICE_CONNECT"
    },
    {
      subnet_name   = "snet-transit-p-usw1-std"
      subnet_ip     = "10.10.1.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-transit-p-usw1-r-proxy"
      subnet_ip     = "172.16.2.0/24"
      subnet_region = "us-west1"
      purpose       = "REGIONAL_MANAGED_PROXY"
      role          = "ACTIVE"
    },
    {
      subnet_name   = "snet-transit-p-usw1-psc-nat"
      subnet_ip     = "172.16.3.0/24"
      subnet_region = "us-west1"
      purpose       = "PRIVATE_SERVICE_CONNECT"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_transit_vpc_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_transit_vpc_subnets must be valid IPv4 CIDR blocks."
  }
}

# Subnets for production services VPC
variable "prod_services_vpc_subnets" {
  description = "A list of subnets for the production services VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
    purpose       = optional(string)
    role          = optional(string)
  }))
  default = [
    {
      subnet_name   = "snet-services-p-use4-std"
      subnet_ip     = "10.11.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-services-p-usw1-std"
      subnet_ip     = "10.11.1.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_services_vpc_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_services_vpc_subnets must be valid IPv4 CIDR blocks."
  }
}

# Subnets for production App 1 VPC
variable "prod_app1_base_subnets" {
  description = "A list of base subnets for the production App 1 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app1-p-use4-client"
      subnet_ip     = "10.12.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-use4-web"
      subnet_ip     = "10.12.1.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-use4-psc-ep"
      subnet_ip     = "10.12.2.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-usw1-client"
      subnet_ip     = "10.12.3.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app1-p-usw1-web"
      subnet_ip     = "10.12.4.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app1-p-usw1-psc-ep"
      subnet_ip     = "10.12.5.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app1_base_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app1_base_subnets must be valid IPv4 CIDR blocks."
  }
}

# CGN subnets for production App 1 VPC, only created if enable_prod_app1_cgn is true
variable "prod_app1_cgn_subnets" {
  description = "A list of CGN subnets for the production App 1 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app1-p-use4-cgn-client"
      subnet_ip     = "100.64.4.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-use4-cgn-web"
      subnet_ip     = "100.64.5.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-usw1-cgn-client"
      subnet_ip     = "100.64.6.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app1-p-usw1-cgn-web"
      subnet_ip     = "100.64.7.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app1_cgn_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app1_cgn_subnets must be valid IPv4 CIDR blocks."
  }
}

# PUPI subnets for production App 1 VPC, only created if enable_prod_app1_pupi is true
variable "prod_app1_pupi_subnets" {
  description = "A list of PUPI subnets for the production App 1 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app1-p-use4-pupi-client"
      subnet_ip     = "1.2.4.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-use4-pupi-web"
      subnet_ip     = "1.2.5.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app1-p-usw1-pupi-client"
      subnet_ip     = "1.2.6.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app1-p-usw1-pupi-web"
      subnet_ip     = "1.2.7.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app1_pupi_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app1_pupi_subnets must be valid IPv4 CIDR blocks."
  }
}

# Subnets for production App 2 VPC
variable "prod_app2_base_subnets" {
  description = "A list of base subnets for the production App 2 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
    purpose       = optional(string)
    role          = optional(string)
  }))
  default = [
    {
      subnet_name   = "snet-app2-p-use4-client"
      subnet_ip     = "10.13.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-use4-web"
      subnet_ip     = "10.13.1.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-use4-psc-ep"
      subnet_ip     = "10.13.2.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-use4-r-proxy"
      subnet_ip     = "172.17.0.0/24"
      subnet_region = "us-east4"
      purpose       = "REGIONAL_MANAGED_PROXY"
      role          = "ACTIVE"
    },
    {
      subnet_name   = "snet-app2-p-usw1-client"
      subnet_ip     = "10.13.3.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app2-p-usw1-web"
      subnet_ip     = "10.13.4.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app2-p-usw1-psc-ep"
      subnet_ip     = "10.13.5.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app2-p-usw1-r-proxy"
      subnet_ip     = "172.17.1.0/24"
      subnet_region = "us-west1"
      purpose       = "REGIONAL_MANAGED_PROXY"
      role          = "ACTIVE"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app2_base_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app2_base_subnets must be valid IPv4 CIDR blocks."
  }
}

# CGN subnets for production App 2 VPC, only created if enable_prod_app2_cgn is true
variable "prod_app2_cgn_subnets" {
  description = "A list of CGN subnets for the production App 2 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app2-p-use4-cgn-client"
      subnet_ip     = "100.64.8.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-use4-cgn-web"
      subnet_ip     = "100.64.9.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-usw1-cgn-client"
      subnet_ip     = "100.64.10.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app2-p-usw1-cgn-web"
      subnet_ip     = "100.64.11.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app2_cgn_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app2_cgn_subnets must be valid IPv4 CIDR blocks."
  }
}

# PUPI subnets for production App 2 VPC, only created if enable_prod_app2_pupi is true
variable "prod_app2_pupi_subnets" {
  description = "A list of PUPI subnets for the production App 2 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app2-p-use4-pupi-client"
      subnet_ip     = "1.2.8.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-use4-pupi-web"
      subnet_ip     = "1.2.9.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app2-p-usw1-pupi-client"
      subnet_ip     = "1.2.10.0/24"
      subnet_region = "us-west1"
    },
    {
      subnet_name   = "snet-app2-p-usw1-pupi-web"
      subnet_ip     = "1.2.11.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app2_pupi_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app2_pupi_subnets must be valid IPv4 CIDR blocks."
  }
}

# Subnets for production App 3 VPC
variable "prod_app3_base_subnets" {
  description = "A list of base subnets for the production App 3 VPC."
  type = list(object({
    subnet_name   = string
    subnet_ip     = string
    subnet_region = string
  }))
  default = [
    {
      subnet_name   = "snet-app3-p-use4-std"
      subnet_ip     = "10.14.0.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name   = "snet-app3-p-usw1-std"
      subnet_ip     = "10.14.1.0/24"
      subnet_region = "us-west1"
    }
  ]

  validation {
    condition     = alltrue([for s in var.prod_app3_base_subnets : can(cidrhost(s.subnet_ip, 0))])
    error_message = "All subnet_ip values in prod_app3_base_subnets must be valid IPv4 CIDR blocks."
  }
}

variable "regions" {
  description = "Primary and secondary regions for lab deployment."
  type = object({
    primary   = string
    secondary = string
  })
  default = {
    primary   = "us-east4"
    secondary = "us-west1"
  }
}

variable "vpc_mtu" {
  description = "Maximum Transmission Unit (MTU) in bytes for all provisioned VPC networks."
  type        = number
  default     = 1500

  validation {
    condition     = var.vpc_mtu >= 1300 && var.vpc_mtu <= 8896
    error_message = "vpc_mtu must be between 1300 and 8896 bytes."
  }
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on service projects."
  type        = bool
  default     = false
}

variable "enable_ncc" {
  description = "Whether to provision the Network Connectivity Center (NCC) hub and spokes. Cannot be true at the same time as enable_vpc_peering."
  type        = bool
  default     = false
}

variable "enable_vpc_peering" {
  description = "Whether to provision VPC Network Peering between the production transit VPC and application VPCs. Cannot be true at the same time as enable_ncc."
  type        = bool
  default     = false

  validation {
    condition     = !(var.enable_ncc && var.enable_vpc_peering)
    error_message = "enable_ncc and enable_vpc_peering cannot both be set to true at the same time. Please enable only one connectivity pattern."
  }
}
