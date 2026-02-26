# Self Managed Inference Gateway Routing Examples

This guide provides common configuration patterns for the Self Managed Inference Gateway module, focusing on model-based routing, cross-platform matching (GKE and Vertex AI), and A/B testing.

## Prerequisites

All examples assume the `body_based_routing` is enabled to extract the model name from the request body.

```hcl
body_based_routing = {
  enabled = true
}
```

---

## 1. Exact Model Matching (GKE and Vertex AI)

Use `header_rules` with `match_type = "exact"` to ensure a specific model name is routed to a specific backend. This is useful when you have specific versions of models deployed on different platforms.

```hcl
backends = {
  default = "gke-pool"
  services = {
    "gke-pool"  = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/gke-neg" }
    "vertex-ai" = { internet_fqdn = "YOUR_REGION-aiplatform.googleapis.com" }
  }
}

routing = {
  header_rules = [
    {
      priority    = 10
      backend     = "vertex-ai"
      header_name = "X-Gateway-Model-Name"
      match_type  = "exact"
      match_value = "gemini-1.5-pro"
    },
    {
      priority    = 20
      backend     = "gke-pool"
      header_name = "X-Gateway-Model-Name"
      match_type  = "exact"
      match_value = "gemma-2-9b-it"
    }
  ]
}
```

**Test this configuration:**

```bash
# Route to Vertex AI (gemini-1.5-pro)
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemini-1.5-pro", "messages": [{"role": "user", "content": "Hello"}]}'

# Route to GKE (gemma-2-9b-it)
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-2-9b-it", "messages": [{"role": "user", "content": "Hello"}]}'
```

---

## 2. Partial Matching and Model Prefixing

Use `model_rules` to route based on prefixes. This allows you to catch all versions of a model family (e.g., all `gemma` models) and route them to a specialized GKE GPU pool.

```hcl
backends = {
  default = "gke-default"
  services = {
    "gke-default"    = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/default-neg" }
    "gke-gemma-pool" = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/gemma-neg" }
    "vertex-ai"      = { internet_fqdn = "YOUR_REGION-aiplatform.googleapis.com" }
  }
}

routing = {
  model_rules = [
    {
      priority     = 50
      backend      = "gke-gemma-pool"
      model_prefix = "gemma"
    },
    {
      priority     = 60
      backend      = "vertex-ai"
      model_prefix = "gemini"
    }
  ]
}
```

**Test this configuration:**

```bash
# Any gemma model routes to gke-gemma-pool
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-3-27b-it", "messages": [{"role": "user", "content": "Hello"}]}'

# Any gemini model routes to vertex-ai
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemini-1.5-flash", "messages": [{"role": "user", "content": "Hello"}]}'
```

---

## 3. Cross-Platform Redundancy (Gemma on Vertex vs. GKE)

You can define separate backends for the same model family on different platforms and use priority to prefer one over the other.

```hcl
backends = {
  default = "vertex-ai"
  services = {
    "gke-gemma" = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/gke-gemma-neg" }
    "vertex-ai" = { internet_fqdn = "YOUR_REGION-aiplatform.googleapis.com" }
  }
}

routing = {
  model_rules = [
    # Prefer GKE for Gemma if available (Priority 10)
    {
      priority     = 10
      backend      = "gke-gemma"
      model_prefix = "gemma"
    },
    # Fallback to Vertex AI for Gemini or if GKE rule doesn't match
    {
      priority     = 20
      backend      = "vertex-ai"
      model_prefix = "gemini"
    }
  ]
}
```

---

## 4. A/B Testing using X-Backend-Type

The Self Managed Inference Gateway supports a powerful A/B testing pattern via the `ext_proc` (Body-Based Router). The `ext_proc` can inspect the request (user ID, session, etc.) and inject a `X-Backend-Type` header to override the default routing.

**Terraform Configuration:**
Define both backends in the module. The Gateway automatically creates high-priority routes for any header named `X-Backend-Type` matching a service name.

```hcl
backends = {
  default = "gke-stable"
  services = {
    "gke-stable"       = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/neg-stable" }
    "gke-experimental" = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/neg-canary" }
  }
}
```

**How it works:**

1. Request arrives with `{ "model": "gemma-2-9b" }`.
2. `ext_proc` calculates if this user (e.g., via `X-User-ID`) should be in the experiment.
3. If yes, `ext_proc` injects `X-Backend-Type: gke-experimental`.
4. The Load Balancer matches the injected header and routes to the experimental pool, ignoring lower priority model/path rules.

**Test this configuration:**

```bash
# Normal request (routes to gke-stable via default routing)
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-2-9b", "messages": [{"role": "user", "content": "Hello"}]}'

# Force experimental backend via header
kubectl exec curl-test -- curl -k -s -X POST \
  https://YOUR_GATEWAY_HOSTNAME/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-Backend-Type: gke-experimental" \
  -d '{"model": "gemma-2-9b", "messages": [{"role": "user", "content": "Hello"}]}'
```

---

## 5. URL Rewriting for Vertex AI Integration

When routing to Vertex AI, you often need to rewrite the path from an OpenAI-compatible format (`/v1/chat/completions`) to the Vertex AI prediction format.

```hcl
backends = {
  default = "gke-default"
  services = {
    "gke-default" = { group = "projects/YOUR_PROJECT_ID/zones/YOUR_ZONE/networkEndpointGroups/default-neg" }
    "vertex-ai"   = { internet_fqdn = "YOUR_REGION-aiplatform.googleapis.com" }
  }
}

routing = {
  model_rules = [
    {
      priority     = 15
      backend      = "vertex-ai"
      model_prefix = "gemini"
      url_rewrite = {
        # Rewrites /v1/chat/completions to the Vertex endpoint
        path_prefix_rewrite = "/v1/projects/YOUR_PROJECT_ID/locations/YOUR_REGION/publishers/google/models/"
        host_rewrite        = "YOUR_REGION-aiplatform.googleapis.com"
      }
    }
  ]
}
```

## 6. Ensuring Seamless Apigee Routing (Reproducibility)

When using GKE Service Extensions (like Semantic Cache) with Apigee, the Load Balancer forwards the client's `Host` header to Apigee. If Apigee doesn't recognize this hostname in an **Environment Group**, it will return a `404 Not Found`.

To ensure your setup is fully reproducible and avoids these errors, the Terraform configuration automatically merges your Gateway hostnames into the Apigee environment group.

### Automatic Merging in Terraform

The root `main.tf` uses a local variable to ensure the `prod` environment group always includes the GKE Gateway's hostname:

```hcl
# Example logic in main.tf
locals {
  final_apigee_envgroups = {
    for k, v in var.apigee_envgroups : k => distinct(concat(
      v,
      k == "prod" && var.gke_gateway != null ? [var.gke_gateway.gateway.hostname] : []
    ))
  }
}
```

### Handling GKE-Internal Authorities

GKE may also generate a unique internal authority (e.g., `apim-enabled-dep-env-group-xxxx.svc.google.com`) for the `ApigeeBackendService`. If you see 404s in your logs despite the gateway hostname being present, add this internal authority to your `extra_apigee_hostnames` in `terraform.tfvars`:

```hcl
# In terraform.tfvars
extra_apigee_hostnames = [
  "apim-enabled-dep-env-group-c78a00a.svc.google.com"
]
```

---

## Summary of Routing Priority

The Gateway evaluates rules in the following order (based on priority numbers):

1. **Direct Backend Overrides:** `X-Backend-Type` header matches (Priority 1-100).
2. **Model Matches:** `model_rules` based on request body (User-defined priority).
3. **Header Matches:** `header_rules` (User-defined priority).
4. **Path Matches:** `path_rules` (User-defined priority).
5. **Default:** `backends.default` service.
