curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/ciandt-dev-2/locations/us-central1/reasoningEngines/5319751165750018048:streamQuery?alt=sse" \
  -d '{
    "class_method": "async_stream_query",
    "input": {
      "user_id": "demo-user",
      "message": "Can u help me describe what are your available class methods at query and streamqueary endpoints?. what are your available classmethods"
    }
  }'