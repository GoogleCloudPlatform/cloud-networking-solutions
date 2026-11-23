# project_id  = "your-project-id"
# region      = "us-central1"
# zone        = "us-central1-a"
# name_prefix = "smig"
# domain_name = "example.com."

# enable_tls         = false
# enable_iap         = true
# enable_model_armor = true
# iap_member         = "user:admin@example.com"

# agents = {
#   agent_a = {
#     host         = "agent-a.example.com"
#     path_prefix  = "/chat"
#     rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
#     backend_host = "us-central1-aiplatform.googleapis.com"
#     backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-a:streamQuery"
#     iap_enabled  = true
#     model_armor  = true
#   }
#   agent_b = {
#     host         = "agent-b.example.com"
#     path_prefix  = "/chat"
#     rewrite_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
#     backend_host = "us-central1-aiplatform.googleapis.com"
#     backend_path = "/v1/projects/1234567890123/locations/us-central1/reasoningEngines/agent-b:streamQuery"
#     iap_enabled  = true
#     model_armor  = false
#   }
# }

consumer_project_id = "self-ingress-dev-1"
producer_project_id = "self-ingress-dev-2"

region = "us-central1"