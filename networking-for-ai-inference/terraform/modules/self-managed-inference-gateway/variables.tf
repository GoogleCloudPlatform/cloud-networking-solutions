

/**
 * Self Managed Inference Gateway Module - Variables
 *
 * Object-based variable structure for clean, maintainable configuration.
 * Reduces 100+ flat variables to ~10 logical groupings.
 */

# ==============================================================================
# REQUIRED VARIABLES
# ==============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
}

# ==============================================================================
# NAMING AND LABELING
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "smg"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# DOMAIN CONFIGURATION
# ==============================================================================

variable "domain" {
  description = <<-EOT
    Domain and SSL/TLS configuration for the gateway.

    Attributes:
    - name: Domain name for the gateway (e.g., inference.example.com)
    - enable_https: Enable HTTPS with SSL certificate (default: true)
    - create_ssl_certificate: Create a new Google-managed SSL certificate (default: true)
    - ssl_certificate_name: Name of existing SSL certificate (if not creating new)
    - use_certificate_manager: Use Certificate Manager instead of self-managed (default: false)
    - certificate_manager_id: Certificate Manager certificate resource URI
    - ssl_private_key: Private key for self-managed certificate (PEM format)
    - ssl_certificate_pem: Certificate in PEM format for self-managed

    Example:
      domain = {
        name                    = "inference.example.com"
        enable_https            = true
        use_certificate_manager = true
        certificate_manager_id  = "projects/my-project/locations/us-east4/certificates/my-cert"
      }
  EOT
  type = object({
    name                    = string
    enable_https            = optional(bool, true)
    create_ssl_certificate  = optional(bool, true)
    ssl_certificate_name    = optional(string)
    use_certificate_manager = optional(bool, false)
    certificate_manager_id  = optional(string)
    ssl_private_key         = optional(string)
    ssl_certificate_pem     = optional(string)
  })
}

# ==============================================================================
# VPC CONFIGURATION
# ==============================================================================

variable "vpc" {
  description = <<-EOT
    VPC and networking configuration.

    Attributes:
    - id: VPC network ID
    - name: VPC network name
    - subnet_id: Subnet ID for the forwarding rule VIP (required for internal LB)
    - proxy_subnet_id: Subnet ID for internal LB proxy (auto-used by load balancer)
    - proxy_subnet_cidr: CIDR range of proxy-only subnet (for firewall rules)
  EOT
  type = object({
    id                = string
    name              = string
    subnet_id         = string
    proxy_subnet_id   = optional(string)
    proxy_subnet_cidr = optional(string)
  })
}

# ==============================================================================
# LOAD BALANCER CONFIGURATION
# ==============================================================================

variable "load_balancer" {
  description = <<-EOT
    Internal load balancer configuration.

    This module only supports Regional Internal Application Load Balancer
    (INTERNAL_MANAGED) for VPC-only access with body-based routing support.

    Attributes:
    - enable_static_ip: Create a static internal IP (default: true)
    - static_ip_name: Name of existing static IP (if not creating new)
    - connection_draining_timeout_sec: Connection draining timeout (default: 300)

    Example:
      load_balancer = {
        enable_static_ip = true
      }
  EOT
  type = object({
    enable_static_ip                = optional(bool, true)
    static_ip_name                  = optional(string)
    connection_draining_timeout_sec = optional(number, 300)
  })
  default = {}
}

# ==============================================================================
# BACKENDS CONFIGURATION
# ==============================================================================

variable "backends" {
  description = <<-EOT
    Flexible backend configurations with extensible types.

    This module supports multiple backend types:
    - GKE NEG (pre-created): Set 'gke_neg' to have Terraform create empty zonal NEGs
      that the GKE NEG controller adopts and populates with endpoints.
    - GKE NEG (existing): Pass full self_links via 'groups' (list for multi-zone)
    - Internet NEG: Auto-created when 'internet_fqdn' is set
    - Hybrid NEG: Pass full self_links via 'groups'
    - Serverless NEG: Pass full self_links via 'groups'

    Attributes:
    - default: Name of default backend (must exist in services map)
    - services: Map of named backend service configurations
      - gke_neg: Pre-create zonal GKE NEGs (Terraform creates, GKE controller fills)
        - name: NEG name (must match K8s Service cloud.google.com/neg annotation)
        - zones: List of zones (e.g., ["us-east4-a", "us-east4-b", "us-east4-c"])
        - network: VPC network (defaults to var.vpc.id)
        - subnetwork: Subnetwork (defaults to var.vpc.subnet_id)
      - groups: List of full self_links or IDs of NEGs (supports multi-zone)
      - internet_fqdn: FQDN for Internet NEG (module creates NEG)
      - internet_port: Port for Internet NEG (default: 443)
      - balancing_mode: RATE, UTILIZATION, or CONNECTION (default: RATE)
      - max_rate_per_endpoint: Max RPS per endpoint (default: 50)
      - capacity_scaler: Capacity scaler 0.0-1.0 (default: 1.0)
      - timeout_sec: Backend timeout (default: 90)
      - protocol: HTTP, HTTPS, or HTTP2 (default: HTTP)
      - health_check: Health check config (null for serverless/internet)

    Note: 'gke_neg', 'groups', and 'internet_fqdn' are mutually exclusive.
    Priority: gke_neg > groups > internet_fqdn.

    Example:
      backends = {
        default = "inference-pool"
        services = {
          "inference-pool" = {
            gke_neg = {
              name  = "inference-pool-neg"
              zones = ["us-east4-a", "us-east4-b", "us-east4-c"]
            }
            health_check = { port = 8000, path = "/health" }
          }
          "vertex-ai" = {
            internet_fqdn  = "aiplatform.googleapis.com"
            internet_port  = 443
            protocol       = "HTTPS"
            balancing_mode = "UTILIZATION"
          }
        }
      }
  EOT
  type = object({
    # Default backend name (must exist in services map)
    default = string

    # Named backend services
    services = map(object({
      # Pre-create zonal GKE NEGs (Terraform creates empty NEGs, GKE controller fills them)
      # The NEG name must match the K8s Service cloud.google.com/neg annotation.
      # Mutually exclusive with 'groups' and 'internet_fqdn'.
      gke_neg = optional(object({
        name       = string           # Must match K8s Service cloud.google.com/neg annotation
        zones      = list(string)     # e.g. ["us-east4-a", "us-east4-b", "us-east4-c"]
        network    = optional(string) # Defaults to var.vpc.id
        subnetwork = optional(string) # Defaults to var.vpc.subnet_id
      }))

      # Backend groups - list of full self_links or IDs (supports multi-zone NEGs)
      # Examples:
      #   GKE NEG (multi-zone): [
      #     "projects/my-project/zones/us-east4-a/networkEndpointGroups/my-neg",
      #     "projects/my-project/zones/us-east4-b/networkEndpointGroups/my-neg",
      #   ]
      #   Serverless NEG: ["projects/my-project/regions/us-east4/networkEndpointGroups/my-neg"]
      #   Internet NEG: Created by this module if internet_fqdn is set
      groups = optional(list(string))

      # For Internet NEG backends (module creates the NEG)
      internet_fqdn = optional(string) # e.g., "aiplatform.googleapis.com"
      internet_port = optional(number, 443)

      # Balancing configuration
      balancing_mode        = optional(string, "RATE") # RATE, UTILIZATION, CONNECTION
      max_rate_per_endpoint = optional(number, 50)
      capacity_scaler       = optional(number, 1.0)

      # Common settings
      timeout_sec = optional(number, 90)
      protocol    = optional(string, "HTTP") # HTTP, HTTPS, HTTP2

      # Health check (null for serverless/internet NEGs)
      health_check = optional(object({
        port = number
        path = string
      }))
    }))
  })

  validation {
    condition = alltrue([
      for k, v in var.backends.services :
      length([for x in [v.gke_neg != null, v.groups != null, v.internet_fqdn != null] : x if x]) <= 1
    ])
    error_message = "Each backend service must use at most one of 'gke_neg', 'groups', or 'internet_fqdn'. They are mutually exclusive."
  }
}

# ==============================================================================
# ROUTING CONFIGURATION
# ==============================================================================

variable "routing" {
  description = <<-EOT
    Flexible routing configuration for model-based, header-based, and path-based routing.

    All routing rules reference backend names defined in var.backends.services.

    Attributes:
    - model_rules: Route based on model name in X-Gateway-Model-Name header
      - priority: Rule priority (lower = higher priority)
      - backend: Backend name (must exist in backends.services)
      - model_prefix: Model name prefix to match
      - url_rewrite: Optional URL rewrite configuration
    - header_rules: Route based on any header value
      - priority: Rule priority
      - backend: Backend name
      - header_name: Header to match
      - match_type: "exact", "prefix", or "regex"
      - match_value: Value to match
    - path_rules: Route based on URL path
      - priority: Rule priority
      - backend: Backend name
      - path_match: Path prefix to match

    Example:
      routing = {
        model_rules = [
          { priority = 10, backend = "vertex-ai", model_prefix = "gemini" },
          { priority = 20, backend = "inference-pool", model_prefix = "gemma" },
          { priority = 30, backend = "inference-pool", model_prefix = "llama" },
        ]
        path_rules = [
          { priority = 200, backend = "inference-pool", path_match = "/v1/chat" },
        ]
      }
  EOT
  type = object({
    # Model-based routing (uses body_based_routing header)
    model_rules = optional(list(object({
      priority     = number
      backend      = string # References backends.services key
      model_prefix = string
      url_rewrite = optional(object({
        path_prefix_rewrite = string
        host_rewrite        = optional(string)
      }))
    })), [])

    # Header-based routing rules
    header_rules = optional(list(object({
      priority    = number
      backend     = string # References backends.services key
      header_name = string
      match_type  = string # "exact", "prefix", "regex"
      match_value = string
      description = optional(string)
    })), [])

    # Path-based routing rules
    path_rules = optional(list(object({
      priority    = number
      backend     = string # References backends.services key
      path_match  = string # Prefix match
      description = optional(string)
      url_rewrite = optional(object({
        path_prefix_rewrite = optional(string)
        host_rewrite        = optional(string)
      }))
    })), [])
  })
  default = {}
}

# ==============================================================================
# BODY-BASED ROUTING CONFIGURATION
# ==============================================================================

variable "body_based_routing" {
  description = <<-EOT
    Body-Based Routing (BBR) configuration using ext_proc.

    BBR extracts the 'model' field from OpenAI-compatible request bodies
    and injects it as a header for routing decisions.

    Attributes:
    - enabled: Enable BBR via ext_proc service extension (default: false)
    - ext_proc: ext_proc service configuration (deployed via service-extension module)
      - image: Container image for BBR ext_proc gRPC service
      - cpu_limit: CPU limit for Cloud Run service
      - memory_limit: Memory limit for Cloud Run service
      - min_instances: Minimum instances (default: 1)
      - max_instances: Maximum instances (default: 10)
    - match_expression: CEL expression for request matching
    - model_header_name: Header name for extracted model (default: X-Gateway-Model-Name)
    - fail_open: Continue on ext_proc failure (default: true)

    Example:
      body_based_routing = {
        enabled = true
        ext_proc = {
          image         = "us-docker.pkg.dev/my-project/images/bbr:v1"
          min_instances = 2
        }
        match_expression = "request.method == 'POST' && request.path.startsWith('/v1/')"
      }
  EOT
  type = object({
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
  })
  default = { enabled = false }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "security" {
  description = <<-EOT
    Security configuration for Model Armor, Cloud Armor, and IAP.

    Attributes:
    - model_armor: Model Armor configuration
      - enabled: Enable Model Armor traffic extension (default: false)
      - service_name: Model Armor service name
      - config: JSON configuration for Model Armor settings
      - match_expression: CEL expression for request matching
    - cloud_armor: Cloud Armor configuration
      - enabled: Enable Cloud Armor security policy (default: false)
      - policy_name: Name of Cloud Armor policy
      - rate_limit_threshold: Rate limit (requests per minute)
    - iap: Identity-Aware Proxy configuration
      - oauth_client_id: OAuth client ID
      - oauth_client_secret: OAuth client secret

    Example:
      security = {
        model_armor = {
          enabled          = true
          match_expression = "request.headers['X-Gateway-Model-Name'].startsWith('gemini')"
        }
        cloud_armor = {
          enabled              = true
          rate_limit_threshold = 1000
        }
      }
  EOT
  type = object({
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

    iap = optional(object({
      oauth_client_id     = optional(string)
      oauth_client_secret = optional(string)
    }), {})
  })
  default = {}
}

# ==============================================================================
# HEALTH CHECK CONFIGURATION
# ==============================================================================

variable "health_check" {
  description = <<-EOT
    Shared health check configuration for all backends.

    Attributes:
    - interval_sec: Health check interval (default: 10)
    - timeout_sec: Health check timeout (default: 5)
    - healthy_threshold: Consecutive successes for healthy (default: 2)
    - unhealthy_threshold: Consecutive failures for unhealthy (default: 3)

    Example:
      health_check = {
        interval_sec       = 15
        unhealthy_threshold = 5
      }
  EOT
  type = object({
    interval_sec        = optional(number, 10)
    timeout_sec         = optional(number, 5)
    healthy_threshold   = optional(number, 2)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

# ==============================================================================
# FIREWALL CONFIGURATION
# ==============================================================================

variable "firewall" {
  description = <<-EOT
    Firewall configuration for health checks and backend access.

    Attributes:
    - create_rules: Create firewall rules (default: true)
    - health_check_ranges: CIDR ranges for health checks

    Example:
      firewall = {
        create_rules = true
      }
  EOT
  type = object({
    create_rules = optional(bool, true)
    health_check_ranges = optional(list(string), [
      "35.191.0.0/16",
      "130.211.0.0/22",
      "209.85.152.0/22",
      "209.85.204.0/22"
    ])
  })
  default = {}
}

# ==============================================================================
# LOGGING CONFIGURATION
# ==============================================================================

variable "logging" {
  description = <<-EOT
    Logging configuration for the gateway.

    Attributes:
    - enable_access_logs: Enable access logging (default: true)
    - sample_rate: Sample rate for access logs 0.0-1.0 (default: 1.0)
    - backend_log_sample_rate: Backend service log sample rate (default: 0.1)

    Example:
      logging = {
        enable_access_logs = true
        sample_rate        = 0.5
      }
  EOT
  type = object({
    enable_access_logs      = optional(bool, true)
    sample_rate             = optional(number, 1.0)
    backend_log_sample_rate = optional(number, 0.1)
  })
  default = {}

  validation {
    condition     = var.logging.sample_rate >= 0.0 && var.logging.sample_rate <= 1.0
    error_message = "logging.sample_rate must be between 0.0 and 1.0"
  }
}
