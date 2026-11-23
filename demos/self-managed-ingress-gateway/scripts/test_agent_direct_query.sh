curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/ciandt-dev-2/locations/us-central1/reasoningEngines/5319751165750018048:query" \
  -d '{
    "input": {
      "input": "What is the exchange rate from US dollars to PEN today?"
    }
  }'