# Complete Example: Apigee Semantic Proxy

This example demonstrates how to deploy a complete Apigee semantic caching proxy with Vertex AI integration.

## Prerequisites

Before you begin, ensure you have:
1.  **An Apigee X Organization:** An active organization is required for proxy deployment.
2.  **A Vertex AI Index:** Create a vector index to support semantic similarity search.
3.  **A Vertex AI Index Endpoint:** Deploy your index to a public or private endpoint.
4.  **Service Account Permissions:** Ensure your account has the necessary roles for both Apigee and Vertex AI.

---

## Setup Instructions

### 1. Create a Vertex AI Index
Create the index using the `gcloud` CLI. Replace the placeholders with your specific project details.

```bash
gcloud ai indexes create \
  --display-name="semantic-cache-index" \
  --region=YOUR_REGION \
  --project=YOUR_PROJECT_ID \
  --metadata-file=index-metadata.json
```

### 2. Create an Index Endpoint
Deploy your index to an endpoint to make it accessible for queries.

```bash
# Create the endpoint
gcloud ai index-endpoints create \
  --display-name="semantic-cache-endpoint" \
  --region=YOUR_REGION \
  --project=YOUR_PROJECT_ID \
  --public-endpoint-enabled

# Deploy the index to the endpoint
gcloud ai index-endpoints deploy-index YOUR_INDEX_ENDPOINT_ID \
  --deployed-index-id=semantic_cache_deployed \
  --display-name="Semantic Cache" \
  --index=YOUR_INDEX_ID \
  --region=YOUR_REGION \
  --project=YOUR_PROJECT_ID
```

### 3. Configure Terraform Variables
Copy the example variables file and update it with your configuration values.

```bash
cp terraform.tfvars.example terraform.tfvars
# Update terraform.tfvars with your PROJECT_ID, REGION, and INDEX_ID
```

### 4. Deploy the Proxy
Initialize and apply the Terraform configuration to deploy the proxy to Apigee.

```bash
terraform init
terraform apply
```

The module automatically packages the API proxy into a ZIP bundle and deploys it to your specified environment.

---

## Testing the Proxy
Once the deployment completes, you can test the semantic cache by sending requests to the proxy URL.

```bash
# Send an initial request
curl -X POST "YOUR_PROXY_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the capital of France?",
    "temperature": 0.7
  }'

# Send a similar request to test cache hitting
curl -X POST "YOUR_PROXY_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Tell me the capital city of France",
    "temperature": 0.7
  }'
```

---

## Monitoring and Troubleshooting

### Monitoring
- **Apigee Console:** Review proxy analytics for cache hit rates, latency, and error patterns.
- **Cloud Console:** Monitor Vertex AI metrics for index query latency and similarity scores.

### Troubleshooting
- **Permission Denied:** Verify your service account has the `roles/apigee.apiAdmin` and `roles/aiplatform.user` roles.
- **Cache Not Populating:** Ensure your request JSON includes either a `prompt` or `messages[0].content` field.
- **Low Hit Rate:** Adjust the `similarity_threshold` variable. A lower value (e.g., 0.85) will increase cache hits but may return less precise matches.

---

## License
Copyright 2025 Google LLC. Licensed under the Apache License, Version 2.0.
