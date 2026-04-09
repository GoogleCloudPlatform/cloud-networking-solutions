# Self Managed Inference Gateway Module

This module creates a Regional Internal Application Load Balancer with intelligent body-based routing and multi-backend support for serving Large Language Models (LLMs) at scale.

The Self Managed Inference Gateway module creates a **Regional Internal Application Load Balancer** with intelligent body-based routing capabilities and multi-backend support for serving Large Language Models (LLMs) at scale.

- **Body-Based Routing:** Routes requests based on the `model` field in the JSON request body using the `ext_proc` protocol.
- **Multi-Backend Support:** Directs traffic to GKE (vLLM), Vertex AI, or other custom backends.
- **Multi-Zone NEGs:** Supports multiple NEG groups per backend for high availability across zones.
- **HTTP to HTTPS Redirect:** Automatically redirects insecure traffic to HTTPS using a shared VIP.
- **Internal Load Balancing:** Uses the `INTERNAL_MANAGED` scheme for secure, private VPC access.

---

## Architecture

1. **Entry Point:** The load balancer receives client requests on a shared Virtual IP (VIP).
2. **Request Interception:** The `LbRouteExtension` sends the request to an `ext_proc` service running on Cloud Run.
3. **Model Extraction:** The `ext_proc` service parses the JSON body and injects the `X-Gateway-Model-Name` header.
4. **Routing Decision:** The URL Map evaluates the injected header and routes the request to the correct backend service.
5. **Fulfillment:** The request reaches the selected GKE Inference Pool, Vertex AI endpoint, or serverless backend.

---

## Usage Guide

### Basic Configuration (Vertex AI only)

```hcl
module "self_managed_inference_gateway" {
  source = "./modules/self-managed-inference-gateway"

  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"

  vpc = {
    id        = module.networking.vpc_id
    name      = module.networking.vpc_name
    subnet_id = module.networking.subnet_id
  }

  domain = {
    name                   = "smg.gateway.example.com"
    enable_https           = true
    create_ssl_certificate = true
  }

  backends = {
    default = "vertex-ai"
    services = {
      "vertex-ai" = {
        internet_fqdn  = "us-east4-aiplatform.googleapis.com"
        protocol       = "HTTPS"
        balancing_mode = "UTILIZATION"
      }
    }
  }

  body_based_routing = {
    enabled = true
  }
}
```

### Multi-Backend Configuration with Pre-Created GKE NEGs (Recommended)

This approach lets Terraform pre-create empty zonal NEGs. The GKE NEG controller
adopts these NEGs and populates endpoints as pods come up. This eliminates the
two-phase NEG discovery loop and enables single-pass infrastructure deployment.

```hcl
module "self_managed_inference_gateway" {
  source = "./modules/self-managed-inference-gateway"

  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"

  vpc = {
    id        = module.networking.vpc_id
    name      = module.networking.vpc_name
    subnet_id = module.networking.subnet_id
  }

  domain = {
    name         = "smg.example.internal.com"
    enable_https = true
  }

  backends = {
    default = "vertex-ai"
    services = {
      "vertex-ai" = {
        internet_fqdn  = "us-east4-aiplatform.googleapis.com"
        protocol       = "HTTPS"
        balancing_mode = "UTILIZATION"
      }
      "gemma-3-27b-it" = {
        gke_neg = {
          name  = "gemma-3-27b-it-neg"
          zones = ["us-east4-a", "us-east4-b", "us-east4-c"]
        }
        protocol     = "HTTP"
        health_check = { port = 8000, path = "/health" }
      }
    }
  }

  routing = {
    model_rules = [
      { priority = 10, backend = "vertex-ai", model_prefix = "gemini" },
      { priority = 20, backend = "gemma-3-27b-it", model_prefix = "gemma" },
    ]
  }

  body_based_routing = {
    enabled = true
  }
}
```

### Multi-Backend Configuration with Existing NEGs

If you already have NEGs created by the GKE NEG controller, you can pass their
self\_links directly via `groups`:

```hcl
module "self_managed_inference_gateway" {
  source = "./modules/self-managed-inference-gateway"

  project_id = "YOUR_PROJECT_ID"
  region     = "YOUR_REGION"

  vpc = {
    id        = module.networking.vpc_id
    name      = module.networking.vpc_name
    subnet_id = module.networking.subnet_id
  }

  domain = {
    name         = "smg.example.internal.com"
    enable_https = true
  }

  backends = {
    default = "vertex-ai"
    services = {
      "vertex-ai" = {
        internet_fqdn  = "us-east4-aiplatform.googleapis.com"
        protocol       = "HTTPS"
        balancing_mode = "UTILIZATION"
      }
      "gemma-3-27b-it" = {
        groups = [
          "projects/YOUR_PROJECT_ID/zones/us-east4-a/networkEndpointGroups/gemma-3-27b-it-neg",
          "projects/YOUR_PROJECT_ID/zones/us-east4-b/networkEndpointGroups/gemma-3-27b-it-neg",
        ]
        protocol     = "HTTP"
        health_check = { port = 8000, path = "/health" }
      }
    }
  }

  routing = {
    model_rules = [
      { priority = 10, backend = "vertex-ai", model_prefix = "gemini" },
      { priority = 20, backend = "gemma-3-27b-it", model_prefix = "gemma" },
    ]
  }

  body_based_routing = {
    enabled = true
  }
}
```

### Adding a New Backend Type

The `backends.services` map accepts any backend that can be expressed as one of (mutually exclusive):

1. **Pre-created GKE NEG** (`gke_neg`): Terraform creates empty zonal NEGs that the GKE NEG controller adopts. This is the recommended approach for GKE backends.
2. **A list of NEG self\_links** (`groups`): For existing GKE NEGs, hybrid, or serverless NEGs. Multi-zone NEGs are supported by providing multiple self\_links.
3. **An internet FQDN** (`internet_fqdn`): The module auto-creates the Internet NEG.

To add a new GKE model backend with pre-created NEGs (recommended):

```hcl
"llama-3-8b" = {
  gke_neg = {
    name  = "llama-3-8b-neg"
    zones = ["us-east4-a", "us-east4-b", "us-east4-c"]
  }
  protocol     = "HTTP"
  health_check = { port = 8000, path = "/health" }
}
```

Then add a corresponding routing rule:

```hcl
routing = {
  model_rules = [
    { priority = 30, backend = "llama-3-8b", model_prefix = "llama" },
  ]
}
```

---

## Adding Additional Models

The `deploy.sh` script deploys `gemma-3-27b-it` by default. To add more GKE-hosted models (e.g., `llama-3-8b`), follow these manual steps:

### 1. Add the backend to tfvars

Add an entry under `self_managed_gateway.backends.services` in your tfvars file. Using `gke_neg` lets Terraform pre-create the NEGs so no discovery step is needed:

```hcl
"llama-3-8b" = {
  gke_neg = {
    name  = "llama-3-8b-neg"
    zones = ["us-east4-a", "us-east4-b", "us-east4-c"]
  }
  protocol     = "HTTP"
  health_check = { port = 8000, path = "/health" }
}
```

### 2. Add a routing rule

Add an entry under `self_managed_gateway.routing.model_rules`:

```hcl
{ priority = 30, backend = "llama-3-8b", model_prefix = "llama" },
```

### 3. Apply Terraform

```bash
cd terraform
terraform apply -var-file="diy-gateway.tfvars"
```

### 4. Deploy the model to GKE

Each model needs a `kustomization-diy.yaml` in `kubernetes/inference-gateway/models/<model>/`. Apply it:

```bash
cd kubernetes/inference-gateway/models/llama-3-8b
cp kustomization-diy.yaml kustomization.yaml
cd ../..
kubectl kustomize . | kubectl apply -f -
```

The GKE NEG controller will detect the pre-created NEGs and populate endpoints as pods come up.

### Migrating from `groups` to `gke_neg`

If you previously used `groups` with existing NEGs and want to switch to `gke_neg`, import the existing NEGs into Terraform state first:

```bash
terraform import \
  'module.self_managed_gateway[0].module.gateway.google_compute_network_endpoint_group.gke["llama-3-8b/us-east4-a"]' \
  projects/PROJECT_ID/zones/us-east4-a/networkEndpointGroups/llama-3-8b-neg
```

Repeat for each zone, then replace `groups` with `gke_neg` in your tfvars.

---

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `project_id` | The Google Cloud project ID. | `string` | - | Yes |
| `region` | The region for load balancer resources. | `string` | - | Yes |
| `name_prefix` | Prefix for resource names. | `string` | `"smg"` | No |
| `labels` | Labels to apply to all resources. | `map(string)` | `{}` | No |
| `vpc` | VPC network and subnetwork details (see below). | `object` | - | Yes |
| `domain` | Domain name and HTTPS settings (see below). | `object` | - | Yes |
| `load_balancer` | Internal load balancer configuration (see below). | `object` | `{}` | No |
| `backends` | Configuration for backend services and NEGs (see below). | `object` | - | Yes |
| `routing` | Model-based, header-based, and path-based routing rules (see below). | `object` | `{}` | No |
| `body_based_routing` | BBR ext\_proc configuration (see below). | `object` | `{ enabled = false }` | No |
| `security` | Model Armor and Cloud Armor settings (see below). | `object` | `{}` | No |
| `health_check` | Shared health check configuration (see below). | `object` | `{}` | No |
| `firewall` | Firewall rules configuration (see below). | `object` | `{}` | No |
| `logging` | Access logging configuration (see below). | `object` | `{}` | No |
| `advanced` | Outlier detection, circuit breakers, locality LB (see below). | `object` | `{}` | No |

### `vpc` Object

| Attribute | Type | Description | Required |
|-----------|------|-------------|----------|
| `id` | `string` | VPC network ID. | Yes |
| `name` | `string` | VPC network name. | Yes |
| `subnet_id` | `string` | Subnet ID for the forwarding rule VIP. | Yes |
| `proxy_subnet_id` | `string` | Subnet ID for internal LB proxy. | No |
| `proxy_subnet_cidr` | `string` | CIDR range of proxy-only subnet (for firewall rules). | No |

### `domain` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `name` | `string` | Domain name for the gateway. | - (required) |
| `enable_https` | `bool` | Enable HTTPS with SSL certificate. | `true` |
| `create_ssl_certificate` | `bool` | Create a new Google-managed SSL certificate. | `true` |
| `ssl_certificate_name` | `string` | Name of existing SSL certificate. | `null` |
| `use_certificate_manager` | `bool` | Use Certificate Manager instead of self-managed. | `false` |
| `certificate_manager_id` | `string` | Certificate Manager certificate resource URI. | `null` |

### `load_balancer` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `enable_static_ip` | `bool` | Create a static internal IP. | `true` |
| `static_ip_name` | `string` | Name of existing static IP. | `null` |
| `connection_draining_timeout_sec` | `number` | Connection draining timeout. | `300` |

### `body_based_routing` Object

| Attribute | Type | Description | Default |
|-----------|------|-------------|---------|
| `enabled` | `bool` | Enable BBR via ext\_proc service extension. | `false` |
| `ext_proc.image` | `string` | Container image for BBR ext\_proc gRPC service. | Gateway API reference image |
| `ext_proc.min_instances` | `number` | Minimum Cloud Run instances. | `1` |
| `ext_proc.max_instances` | `number` | Maximum Cloud Run instances. | `10` |
| `match_expression` | `string` | CEL expression for request matching. | `"true"` |
| `model_header_name` | `string` | Header name for extracted model. | `"X-Gateway-Model-Name"` |
| `fail_open` | `bool` | Continue on ext\_proc failure. | `true` |

### Backend Service Fields

| Field | Description | Default |
|-------|-------------|---------|
| `gke_neg` | Pre-create zonal GKE NEGs (see below). Mutually exclusive with `groups` and `internet_fqdn`. | `null` |
| `groups` | List of NEG self\_links (supports multi-zone). | `null` |
| `internet_fqdn` | FQDN for auto-created Internet NEG. | `null` |
| `internet_port` | Port for Internet NEG. | `443` |
| `balancing_mode` | `RATE`, `UTILIZATION`, or `CONNECTION`. | `RATE` |
| `max_rate_per_endpoint` | Max RPS per endpoint (when `RATE`). | `50` |
| `capacity_scaler` | Capacity scaler 0.0-1.0. | `1.0` |
| `timeout_sec` | Backend timeout in seconds. | `90` |
| `protocol` | `HTTP`, `HTTPS`, or `HTTP2`. | `HTTP` |
| `health_check` | Health check config `{ port, path }`. | `null` |

### `gke_neg` Object

| Attribute | Type | Description | Required |
|-----------|------|-------------|----------|
| `name` | `string` | NEG name (must match K8s Service `cloud.google.com/neg` annotation). | Yes |
| `zones` | `list(string)` | List of zones for the zonal NEGs (e.g., `["us-east4-a", "us-east4-b"]`). | Yes |
| `network` | `string` | VPC network (defaults to `var.vpc.id`). | No |
| `subnetwork` | `string` | Subnetwork (defaults to `var.vpc.subnet_id`). | No |

---

## Outputs

| Name | Description |
|------|-------------|
| `gateway_ip` | The shared VIP address for the gateway. |
| `gateway_url` | The full HTTPS URL for reaching the gateway. |
| `gke_neg_self_links` | Map of backend name to list of pre-created GKE NEG self\_links. |
| `bbr_ext_proc_service_url` | The URL of the `ext_proc` service on Cloud Run. |

## Resources Created

### Load Balancer Resources

- `google_compute_address` - Shared VIP with `SHARED_LOADBALANCER_VIP` purpose
- `google_compute_region_url_map` - Main URL map for routing
- `google_compute_region_url_map` - HTTP redirect URL map (when HTTPS enabled)
- `google_compute_region_target_http_proxy` - HTTP proxy
- `google_compute_region_target_https_proxy` - HTTPS proxy
- `google_compute_forwarding_rule` - HTTP forwarding rule (port 80)
- `google_compute_forwarding_rule` - HTTPS forwarding rule (port 443)
- `google_compute_region_ssl_certificate` - SSL certificate (if created)

### Backend Resources

- `google_compute_region_backend_service` - Backend services for each configured backend
- `google_compute_region_health_check` - Health checks for each backend
- `google_compute_network_endpoint_group` - Zonal GKE NEGs (pre-created for NEG controller adoption)
- `google_compute_region_network_endpoint_group` - Internet NEGs for external backends

### Body-Based Routing Resources

- `google_cloud_run_service` - ext_proc Cloud Run service
- `google_compute_region_network_endpoint_group` - Serverless NEG for ext_proc
- `google_compute_region_backend_service` - Backend service for ext_proc
- `google_network_services_lb_route_extension` - Route extension for body-based routing

### Security Resources

- `google_compute_firewall` - Health check firewall rules
- `google_service_account` - Service account for ext_proc

## Testing

### Test HTTP to HTTPS Redirect

```bash
# Should return 301 redirect to HTTPS
curl -v http://smg.example.com/v1/chat/completions
```

### Test Body-Based Routing (Gemma --> GKE)

```bash
curl -k https://smg.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-3-27b-it", "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 10}'
```

### Test Body-Based Routing (Gemini --> Vertex AI)

```bash
TOKEN=$(gcloud auth print-access-token)
curl -k https://smg.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"model": "google/gemini-3-flash-preview", "messages": [{"role": "user", "content": "Say hi"}], "max_tokens": 10}'
```

### Test Direct Backend Routing (via header)

```bash
# Force routing to GKE backend regardless of model
curl -k https://smg.example.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Backend-Type: gke" \
  -d '{"model": "any-model", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Troubleshooting

### HTTP to HTTPS Redirect Not Working

**Issue**: HTTP requests timeout instead of redirecting

**Solution**:
1. Verify both forwarding rules use the same shared VIP:
   ```bash
   gcloud compute forwarding-rules list --filter="name~smg" --format="table(name,IPAddress,portRange)"
   ```
2. Check the shared VIP has `purpose = SHARED_LOADBALANCER_VIP`:
   ```bash
   gcloud compute addresses describe smg-shared-ip --region=REGION
   ```
3. Verify the HTTP proxy uses the redirect URL map:
   ```bash
   gcloud compute target-http-proxies describe smg-regional-http-proxy --region=REGION
   ```

### Body-Based Routing Returns 404

- Check the `ext_proc` service logs in Cloud Run to ensure it is correctly extracting model names.
- Verify that your URL Map routing rules match the exact model strings being sent in the request body.

**Solution**:
1. Check ext_proc logs:
   ```bash
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="smg-bbr"' --limit=10
   ```
2. Verify the model name matches routing rules (e.g., `google/gemma-3-27b-it` not just `gemma`)
3. Check the URL map routing configuration:
   ```bash
   gcloud compute url-maps describe smg-url-map --region=REGION
   ```

- Verify the Service has the `cloud.google.com/neg` annotation with the correct NEG name.
- Check that the GKE cluster has NEG controller enabled.
- NEGs are created per-zone; use `gcloud compute network-endpoint-groups list --filter="name=NEG_NAME"` to discover all zones.

**Issue**: Requests timeout with 500 error

**Solution**:
1. Verify the ext_proc Cloud Run service is running:
   ```bash
   gcloud run services describe smg-bbr --region=REGION
   ```
2. Check the route extension is attached to the correct forwarding rule:
   ```bash
   # Via REST API
   curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     "https://networkservices.googleapis.com/v1/projects/PROJECT/locations/REGION/lbRouteExtensions/smg-bbr-route-ext"
   ```
3. Ensure the route extension timeout is sufficient (default: 5s)

### Backend Health Check Failures

**Issue**: Backend shows unhealthy

**Solution**:
1. Check backend health:
   ```bash
   gcloud compute backend-services get-health smg-gke --region=REGION
   ```
2. Verify health check configuration matches backend port:
   ```bash
   gcloud compute health-checks describe smg-gke-hc --region=REGION
   ```
3. Check firewall rules allow health check traffic:
   ```bash
   gcloud compute firewall-rules list --filter="name~smg"
   ```

## References

- [HTTP to HTTPS Redirect for Internal ALB](https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-http-to-https-redirect)
- [LbRouteExtension Documentation](https://cloud.google.com/load-balancing/docs/service-extensions/lb-route-extension-overview)
- [ext_proc for Body-Based Routing](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-body-based-routing)
- [Gateway API Inference Extension](https://github.com/GoogleCloudPlatform/gateway-api-inference-extension)

## License

Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
