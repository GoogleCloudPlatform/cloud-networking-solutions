/**
 * Root Terraform Variables
 *
 * This file defines input variables for the inference gateway infrastructure.
 * Object-based variables reduce sprawl and improve maintainability.
 *
 * Gateway approaches:
 * - self_managed_gateway: Self Managed Load Balancer approach with body-based routing
 * - gke_gateway: GKE Gateway API approach (Kubernetes-native)
 *
 * Both can coexist and be enabled simultaneously.
 */

# ==============================================================================
# CORE PROJECT CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "igw"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "inference-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "gke-subnet-us-central1"
}

variable "pods_range_name" {
  description = "Name of the secondary range for pods"
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary range for services"
  type        = string
  default     = "services"
}

variable "primary_subnet_cidr" {
  description = "CIDR range for the primary subnet"
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR range for GKE pods"
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "CIDR range for GKE services"
  type        = string
  default     = "10.8.0.0/20"
}

variable "proxy_subnet_cidr" {
  description = "CIDR range for the proxy-only subnet"
  type        = string
  default     = "10.9.0.0/24"
}

variable "gateway_scope" {
  description = "Gateway scope: 'regional' for regional internal gateway, or null to skip gateway provisioning"
  type        = string
  default     = "regional"
  validation {
    condition     = var.gateway_scope == null || contains(["regional"], var.gateway_scope)
    error_message = "gateway_scope must be 'regional' or null"
  }
}

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================

variable "dns_zone_domain" {
  description = "The domain name for the public DNS zone (must end with a dot, e.g., 'example.com.')"
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "The name of the existing Cloud DNS managed zone. If not provided, derived from dns_zone_domain."
  type        = string
  default     = null
}

variable "enable_certificate_manager" {
  description = "Enable Certificate Manager to create managed certificates for the DNS domain"
  type        = bool
  default     = false
}

variable "internal_gateway_hostname" {
  description = "Override hostname for internal gateway. If not set, derived from dns_zone_domain as {internal_gateway_subdomain}.{dns_zone_domain}"
  type        = string
  default     = null
}

# ==============================================================================
# SECRETS CONFIGURATION
# ==============================================================================

variable "huggingface_token" {
  description = "Hugging Face API token for model downloads. If provided, will be stored in Secret Manager"
  type        = string
  sensitive   = true
  default     = null
}

variable "huggingface_secret_id" {
  description = "Secret ID for HuggingFace token in Secret Manager"
  type        = string
  default     = "huggingface-token"
}

variable "enable_secret_manager" {
  description = "Enable Secret Manager integration for GKE nodes (grants secretAccessor role to node service account)"
  type        = bool
  default     = true
}

variable "model_namespaces" {
  description = "List of Kubernetes namespaces for AI models that need access to Secret Manager"
  type        = list(string)
  default     = ["default", "gemma-3-27b-it", "llama-3-8b"]
}

# ==============================================================================
# ARTIFACT REGISTRY CONFIGURATION
# ==============================================================================

variable "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "images"
}

variable "artifact_registry_description" {
  description = "Description for the Artifact Registry repository"
  type        = string
  default     = "Docker image repository for model inference containers"
}

variable "artifact_registry_immutable_tags" {
  description = "Enable immutable tags for Docker images"
  type        = bool
  default     = false
}

# ==============================================================================
# GKE CLUSTERS CONFIGURATION
# ==============================================================================

variable "clusters" {
  description = "Map of GKE cluster configurations. Each cluster can specify dns_domain, deletion_protection, and secret_sync_config for syncing secrets from Secret Manager."
  type = map(object({
    dns_domain          = string
    deletion_protection = optional(bool, true)
    secret_sync_config = optional(object({
      enabled = bool
      rotation_config = optional(object({
        enabled           = optional(bool)
        rotation_interval = optional(string)
      }))
    }))
  }))
  default = {
    inference-cluster = {
      dns_domain          = "inference"
      deletion_protection = true
    }
  }
}

# ==============================================================================
# MODEL ARMOR CONFIGURATION
# ==============================================================================

variable "enable_model_armor" {
  description = "Enable Model Armor template and IAM bindings"
  type        = bool
  default     = false
}

variable "model_armor_template_id" {
  description = "ID for the Model Armor template"
  type        = string
  default     = "default-safety-template"
}

variable "model_armor_rai_filters" {
  description = "RAI (Responsible AI) filter configurations. filter_type can be: SEXUALLY_EXPLICIT, HATE_SPEECH, HARASSMENT, DANGEROUS. confidence_level can be: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH"
  type = list(object({
    filter_type      = string
    confidence_level = string
  }))
  default = [
    {
      filter_type      = "HATE_SPEECH"
      confidence_level = "MEDIUM_AND_ABOVE"
    },
    {
      filter_type      = "HARASSMENT"
      confidence_level = "MEDIUM_AND_ABOVE"
    },
    {
      filter_type      = "SEXUALLY_EXPLICIT"
      confidence_level = "MEDIUM_AND_ABOVE"
    }
  ]
}

variable "model_armor_sdp_enforcement" {
  description = "Sensitive Data Protection filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.model_armor_sdp_enforcement)
    error_message = "model_armor_sdp_enforcement must be ENABLED or DISABLED"
  }
}

variable "model_armor_pii_types" {
  description = "List of PII info types to detect and block"
  type        = list(string)
  default = [
    "US_SOCIAL_SECURITY_NUMBER",
    "CREDIT_CARD_NUMBER",
    "PHONE_NUMBER",
    "EMAIL_ADDRESS",
    "PASSPORT",
    "DATE_OF_BIRTH",
    "MEDICAL_RECORD_NUMBER",
    "IP_ADDRESS",
    "STREET_ADDRESS",
    "PERSON_NAME"
  ]
}

variable "model_armor_pi_jailbreak_enforcement" {
  description = "PI and jailbreak filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
}

variable "model_armor_pi_jailbreak_confidence" {
  description = "PI and jailbreak filter confidence level (LOW_AND_ABOVE, MEDIUM_AND_ABOVE, or HIGH)"
  type        = string
  default     = "LOW_AND_ABOVE"
  validation {
    condition     = contains(["LOW_AND_ABOVE", "MEDIUM_AND_ABOVE", "HIGH"], var.model_armor_pi_jailbreak_confidence)
    error_message = "model_armor_pi_jailbreak_confidence must be one of: LOW_AND_ABOVE, MEDIUM_AND_ABOVE, HIGH"
  }
}

variable "model_armor_malicious_uri_enforcement" {
  description = "Malicious URI filter enforcement setting (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
}

# ==============================================================================
# SEMANTIC CACHE CONFIGURATION (Apigee + Vertex AI)
# ==============================================================================

variable "enable_semantic_cache" {
  description = "Enable Vertex AI Semantic Cache with Apigee integration"
  type        = bool
  default     = false
}

# Vertex AI Index Configuration
variable "vertex_ai_index_dimensions" {
  description = "Number of dimensions for the Vertex AI vector index"
  type        = number
  default     = 768
}

variable "vertex_ai_min_replica_count" {
  description = "Minimum number of replicas for the Vertex AI index endpoint"
  type        = number
  default     = 1
}

variable "vertex_ai_max_replica_count" {
  description = "Maximum number of replicas for the Vertex AI index endpoint"
  type        = number
  default     = 3
}

# Apigee Configuration
variable "apigee_org_display_name" {
  description = "Display name for the Apigee organization"
  type        = string
  default     = "Apigee"
}

variable "apigee_org_description" {
  description = "Description for the Apigee organization"
  type        = string
  default     = "Apigee Organization for API Management"
}

variable "apigee_billing_type" {
  description = "Billing type for Apigee organization (PAYG or SUBSCRIPTION)"
  type        = string
  default     = "PAYG"
  validation {
    condition     = contains(["PAYG", "SUBSCRIPTION"], var.apigee_billing_type)
    error_message = "apigee_billing_type must be either PAYG or SUBSCRIPTION"
  }
}

variable "apigee_analytics_region" {
  description = "Analytics region for Apigee organization (e.g., us-central1, europe-west1, asia-northeast1)"
  type        = string
  default     = "us-central1"
}

variable "apigee_runtime_type" {
  description = "Runtime type for Apigee organization (CLOUD or HYBRID)"
  type        = string
  default     = "CLOUD"
  validation {
    condition     = contains(["CLOUD", "HYBRID"], var.apigee_runtime_type)
    error_message = "apigee_runtime_type must be either CLOUD or HYBRID"
  }
}

variable "apigee_disable_vpc_peering" {
  description = "Disable automatic VPC peering for Apigee"
  type        = bool
  default     = false
}

variable "apigee_envgroups" {
  description = "Map of environment group names to hostnames"
  type        = map(list(string))
  default = {
    prod = []
  }
}

variable "apigee_environments" {
  description = "Map of Apigee environments"
  type = map(object({
    display_name = string
    description  = optional(string)
    envgroups    = list(string)
    type         = optional(string, "INTERMEDIATE")
    node_config = optional(object({
      min_node_count = optional(number)
      max_node_count = optional(number)
    }))
    properties = optional(map(string))
  }))
  default = {
    apis-prod = {
      display_name = "APIs Production"
      description  = "Production environment for APIs"
      envgroups    = ["prod"]
      type         = "INTERMEDIATE"
    }
  }
}

variable "apigee_instances" {
  description = "Map of Apigee instances by region"
  type = map(object({
    environments                  = list(string)
    runtime_ip_cidr_range         = optional(string)
    troubleshooting_ip_cidr_range = optional(string)
    consumer_accept_list          = optional(list(string))
    disk_encryption_key           = optional(string)
  }))
  default = {}
}

variable "apigee_endpoint_attachments" {
  description = "Map of Apigee endpoint attachments for connecting to backend services via PSC"
  type = map(object({
    region             = string
    service_attachment = string
  }))
  default = {}
}

variable "extra_apigee_hostnames" {
  description = "List of additional hostnames to add to the primary Apigee environment group (e.g., GKE internal authorities)"
  type        = list(string)
  default     = []
}

# ==============================================================================
# SELF MANAGED INFERENCE GATEWAY (Object-based configuration)
# ==============================================================================

variable "self_managed_gateway" {
  description = <<-EOT
    Self Managed Inference Gateway configuration. Set to null to disable.

    This creates a self-managed Regional Internal Application Load Balancer
    with body-based routing for intelligent model routing based on request content.

    Attributes:
    - name_prefix: Prefix for resource names (default: "smg")
    - domain: Domain and SSL/TLS configuration
    - load_balancer: Internal load balancer settings
    - backends: Flexible backend configuration (GKE NEG, Internet NEG, etc.)
    - routing: Model-based, header-based, and path-based routing rules
    - body_based_routing: BBR ext_proc configuration
    - security: Model Armor and Cloud Armor settings
    - health_check: Health check configuration
    - firewall: Firewall rules configuration
    - logging: Access logging configuration

    Example:
      self_managed_gateway = {
        name_prefix = "smg"
        domain = {
          name         = "smg.internal.example.com"
          enable_https = true
        }
        backends = {
          default = "inference-pool"
          services = {
            "inference-pool" = {
              groups = [
                "projects/PROJECT/zones/us-east4-a/networkEndpointGroups/NEG_NAME",
                "projects/PROJECT/zones/us-east4-b/networkEndpointGroups/NEG_NAME",
              ]
              health_check = { port = 8000, path = "/health" }
            }
            "vertex-ai" = {
              internet_fqdn = "aiplatform.googleapis.com"
              protocol      = "HTTPS"
            }
          }
        }
        routing = {
          model_rules = [
            { priority = 10, backend = "vertex-ai", model_prefix = "gemini" },
            { priority = 20, backend = "inference-pool", model_prefix = "gemma" },
          ]
        }
        body_based_routing = {
          enabled = true
        }
      }
  EOT
  type = object({
    name_prefix = optional(string, "smg")

    # Domain configuration
    domain = object({
      name                    = string
      enable_https            = optional(bool, true)
      create_ssl_certificate  = optional(bool, true)
      ssl_certificate_name    = optional(string)
      use_certificate_manager = optional(bool, false)
      certificate_manager_id  = optional(string)
      ssl_private_key         = optional(string)
      ssl_certificate_pem     = optional(string)
    })

    # Internal load balancer configuration
    load_balancer = optional(object({
      enable_static_ip                = optional(bool, true)
      static_ip_name                  = optional(string)
      connection_draining_timeout_sec = optional(number, 300)
    }), {})

    # Flexible backends configuration
    backends = object({
      # Default backend name (must exist in services map)
      default = string

      # Named backend services
      services = map(object({
        # Pre-create zonal GKE NEGs (Terraform creates empty NEGs, GKE controller fills them)
        gke_neg = optional(object({
          name       = string           # Must match K8s Service cloud.google.com/neg annotation
          zones      = list(string)     # e.g. ["us-east4-a", "us-east4-b", "us-east4-c"]
          network    = optional(string) # Defaults to var.vpc.id
          subnetwork = optional(string) # Defaults to var.vpc.subnet_id
        }))

        # Backend groups - list of full self_links or IDs (supports multi-zone NEGs)
        groups = optional(list(string))

        # For Internet NEG backends (module creates the NEG)
        internet_fqdn = optional(string)
        internet_port = optional(number, 443)

        # Balancing configuration
        balancing_mode        = optional(string, "RATE")
        max_rate_per_endpoint = optional(number, 50)
        capacity_scaler       = optional(number, 1.0)

        # Common settings
        timeout_sec = optional(number, 90)
        protocol    = optional(string, "HTTP")

        # Health check (null for serverless/internet NEGs)
        health_check = optional(object({
          port = number
          path = string
        }))
      }))
    })

    # Flexible routing configuration
    routing = optional(object({
      # Model-based routing (uses body_based_routing header)
      model_rules = optional(list(object({
        priority     = number
        backend      = string
        model_prefix = string
        url_rewrite = optional(object({
          path_prefix_rewrite = string
          host_rewrite        = optional(string)
        }))
      })), [])

      # Header-based routing rules
      header_rules = optional(list(object({
        priority    = number
        backend     = string
        header_name = string
        match_type  = string
        match_value = string
        description = optional(string)
      })), [])

      # Path-based routing rules
      path_rules = optional(list(object({
        priority    = number
        backend     = string
        path_match  = string
        description = optional(string)
      })), [])
    }), {})

    # Body-based routing configuration (ext_proc only)
    body_based_routing = optional(object({
      enabled = optional(bool, false)

      ext_proc = optional(object({
        image         = optional(string, "")
        cpu_limit     = optional(string, "1000m")
        memory_limit  = optional(string, "512Mi")
        min_instances = optional(number, 1)
        max_instances = optional(number, 10)
      }), {})

      match_expression  = optional(string, "true")
      model_header_name = optional(string, "X-Gateway-Model-Name")
      fail_open         = optional(bool, true)
    }), { enabled = false })

    # Security configuration
    security = optional(object({
      model_armor = optional(object({
        enabled          = optional(bool, false)
        service_name     = optional(string)
        template_id      = optional(string, "default-safety-template")
        protected_models = optional(list(string), [])
        config           = optional(string)
        match_expression = optional(string, "true")
        paths            = optional(list(string), [])
        models           = optional(list(string), [])
      }), {})

      cloud_armor = optional(object({
        enabled              = optional(bool, false)
        policy_name          = optional(string)
        rate_limit_threshold = optional(number, 1000)
      }), {})
    }), {})

    # Health check configuration
    health_check = optional(object({
      interval_sec        = optional(number, 10)
      timeout_sec         = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})

    # Firewall configuration
    firewall = optional(object({
      create_rules = optional(bool, true)
      health_check_ranges = optional(list(string), [
        "35.191.0.0/16",
        "130.211.0.0/22",
        "209.85.152.0/22",
        "209.85.204.0/22"
      ])
    }), {})

    # Logging configuration
    logging = optional(object({
      enable_access_logs      = optional(bool, true)
      sample_rate             = optional(number, 1.0)
      backend_log_sample_rate = optional(number, 0.1)
    }), {})
  })
  default = null
}

# ==============================================================================
# GKE INFERENCE GATEWAY (Object-based configuration)
# ==============================================================================

variable "gke_gateway" {
  description = <<-EOT
    GKE Inference Gateway configuration. Set to null to disable.

    Provides the Kubernetes Gateway API configuration used by the DNS module
    (for hostname-based DNS records) and by deploy.sh (for kustomize rendering).
    Static IPs, certificates, and service accounts are managed by the networking,
    certificates, and GKE modules respectively.

    Attributes:
    - gateway: Kubernetes Gateway resource configuration

    Example:
      gke_gateway = {
        gateway = {
          name          = "inference-gateway"
          namespace     = "default"
          hostname      = "inference.gateway.example.com"
          gateway_class = "gke-l7-rilb"
        }
      }
  EOT
  type = object({
    # Gateway configuration
    gateway = object({
      name          = optional(string, "inference-gateway")
      namespace     = optional(string, "default")
      hostname      = string
      gateway_class = optional(string, "gke-l7-rilb")
    })
  })
  default = null
}
