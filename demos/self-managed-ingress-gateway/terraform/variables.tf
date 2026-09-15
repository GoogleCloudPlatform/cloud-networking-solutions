variable "project_id" {
  description = "The Google Cloud project ID where the demo resources are created."
  type        = string
}

variable "region" {
  description = "The default region for the regional and private networking resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The default zone for destinations and zonal resources."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Short prefix applied to created resources."
  type        = string
  default     = "smig"
}

variable "domain_name" {
  description = "Public domain used by the front door. Example: example.com."
  type        = string
  default     = "example.com."
}

variable "agents" {
  description = "Per-agent hostnames and request rewrite settings for the front door and regional internal gateways."
  type = map(object({
    host         = string
    path_prefix  = string
    rewrite_path = string
    backend_host = string
    backend_path = string
    iap_enabled  = optional(bool, true)
    model_armor  = optional(bool, false)
  }))
  default = {
    agent_a = {
      host         = "agent-a.example.com"
      path_prefix  = "/chat"
      rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
      backend_host = "us-central1-aiplatform.googleapis.com"
      backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
      iap_enabled  = true
      model_armor  = true
    }
    agent_b = {
      host         = "agent-b.example.com"
      path_prefix  = "/chat"
      rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
      backend_host = "us-central1-aiplatform.googleapis.com"
      backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
      iap_enabled  = true
      model_armor  = false
    }
  }
}

variable "enable_tls" {
  description = "If true, create a managed SSL certificate for the public front door."
  type        = bool
  default     = false
}

variable "enable_iap" {
  description = "If true, attach an IAP policy to the per-agent regional backend service."
  type        = bool
  default     = true
}

variable "enable_model_armor" {
  description = "Placeholder switch to surface the Model Armor / ext_proc integration in the design."
  type        = bool
  default     = true
}

variable "iap_member" {
  description = "IAM member used to allow access through IAP. Example: user:alice@example.com"
  type        = string
  default     = "user:admin@example.com"
}
