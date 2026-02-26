#!/bin/bash
# Test script for AI Inference Gateway
# Supports two gateway modes:
#   gke  - GKE Inference Gateway (Gateway API with InferencePool/HTTPRoute)
#   diy  - Self-Managed Inference Gateway (Regional LB with body-based routing)
#
# Usage:
#   GATEWAY_HOST=gateway.example.com ./test_endpoints.sh [gke|diy]

# --- Mode flag parsing ---
MODE="${1:-gke}"
case "$MODE" in
gke)
	MODE="gke"
	;;
diy | self-managed | smg)
	MODE="diy"
	;;
*)
	echo "Error: Invalid mode '$MODE'"
	echo "Usage: GATEWAY_HOST=gateway.example.com ./test_endpoints.sh [gke|diy|self-managed|smg]"
	echo ""
	echo "Modes:"
	echo "  gke              GKE Inference Gateway (default)"
	echo "  diy|self-managed Self-Managed Inference Gateway with body-based routing"
	exit 1
	;;
esac

# --- Common setup ---
GATEWAY_HOST="${GATEWAY_HOST}"
if [ -z "$GATEWAY_HOST" ]; then
	echo "Error: GATEWAY_HOST environment variable is not set."
	echo "Usage: GATEWAY_HOST=gateway.example.com ./test_endpoints.sh [$MODE]"
	exit 1
fi

MODEL_ID="google/gemma-3-27b-it"

# Cleanup function to remove the test pod
cleanup() {
	echo "================================================================"
	echo "Cleaning up: deleting curl-test pod..."
	kubectl delete pod curl-test --ignore-not-found
}

# Trap exit signals to ensure cleanup
trap cleanup EXIT

echo "================================================================"
echo "Deploying curl-test pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: curl-test
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF

echo "Waiting for curl-test pod to be ready..."
kubectl wait --for=condition=Ready pod/curl-test --timeout=120s

# Helper function to send requests via curl inside the pod
# Usage: send_request <path> <json_payload> [extra curl args...]
send_request() {
	local path=$1
	local payload=$2
	shift 2

	echo "$payload" | kubectl exec -i curl-test -- curl -k -s \
		-X POST "https://$GATEWAY_HOST$path" \
		-H "Content-Type: application/json" \
		"$@" \
		-d @-
}

echo "================================================================"
echo "Mode: $MODE"
echo "Host: $GATEWAY_HOST"
echo "================================================================"

# =============================================================================
# GKE Inference Gateway Tests
# =============================================================================
if [ "$MODE" = "gke" ]; then

	echo ""
	echo "================================================================"
	echo "1. Testing Standard Inference (/v1/)"
	echo "   Route: HTTPRoute -> InferencePool (Gemma via vLLM)"
	echo "================================================================"
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "Explain body-based routing in one sentence."}]
	}'
	send_request "/v1/chat/completions" "$PAYLOAD"
	echo -e "\n"

	echo "================================================================"
	echo "2. Testing Semantic Cache (/cache/)"
	echo "   Route: HTTPRoute -> Apigee Semantic Proxy -> InferencePool"
	echo "================================================================"
	echo "Step A: Performing first request (Cache Miss)..."
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "What is the capital of France?"}]
	}'
	send_request "/cache/v1/chat/completions" "$PAYLOAD"

	echo -e "\n\nStep B: Performing second request (Cache Hit - Should be much faster)..."
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "Tell me the capital of France."}]
	}'
	send_request "/cache/v1/chat/completions" "$PAYLOAD" -i
	echo -e "\n"

	echo "================================================================"
	echo "3. Testing Model Armor (/security/)"
	echo "   Route: HTTPRoute -> Model Armor filter -> InferencePool"
	echo "   Expected: HTTP 799 (PII blocked)"
	echo "================================================================"
	echo "Sending prompt with PII (Model Armor should block or filter this)..."
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "My social security number is 123-45-6789."}]
	}'
	send_request "/security/v1/chat/completions" "$PAYLOAD" -i
	echo -e "\n"

# =============================================================================
# DIY / Self-Managed Inference Gateway Tests
# =============================================================================
elif [ "$MODE" = "diy" ]; then

	echo ""
	echo "================================================================"
	echo "1. Testing Gemma -> GKE (Body-Based Routing)"
	echo "   BBR extracts model='$MODEL_ID' from request body"
	echo "   Sets header X-Gateway-Model-Name: $MODEL_ID"
	echo "   URL map prefix match 'google/gemma' -> GKE backend (vLLM)"
	echo "================================================================"
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "Explain body-based routing in one sentence."}]
	}'
	send_request "/v1/chat/completions" "$PAYLOAD"
	echo -e "\n"

	echo "================================================================"
	echo "2. Testing Gemini -> Vertex AI (Body-Based Routing)"
	echo "   BBR extracts model='gemini-2.5-flash' from request body"
	echo "   Sets header X-Gateway-Model-Name: gemini-2.5-flash"
	echo "   URL map prefix match 'gemini' -> Vertex AI backend"
	echo "   Backend: us-east4-aiplatform.googleapis.com (Internet NEG)"
	echo "================================================================"
	echo "Obtaining access token for Vertex AI..."
	TOKEN=$(gcloud auth print-access-token 2>/dev/null)
	if [ -z "$TOKEN" ]; then
		echo "WARNING: Could not obtain access token. Skipping Vertex AI test."
		echo "Run 'gcloud auth login' or ensure application default credentials."
	else
		PAYLOAD='{
		  "model": "google/gemini-2.5-flash",
		  "messages": [{"role": "user", "content": "What is 2+2? Reply with just the number."}]
		}'
		send_request "/v1/chat/completions" "$PAYLOAD" -H "Authorization: Bearer $TOKEN" -i
		echo -e "\n"
	fi

	echo "================================================================"
	echo "3. Testing Model Armor (/security/)"
	echo "   Path rule /security/ (priority 6) -> gemma-3-27b-it backend"
	echo "   Model Armor ext_proc filters PII before reaching backend"
	echo "   Expected: HTTP 799 (PII blocked)"
	echo "================================================================"
	echo "Sending prompt with PII (Model Armor should block or filter this)..."
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "My social security number is 123-45-6789."}]
	}'
	send_request "/security/v1/chat/completions" "$PAYLOAD" -i
	echo -e "\n"

	echo "================================================================"
	echo "4. Testing Backend Override (X-Backend-Type header)"
	echo "   Sends X-Backend-Type: gemma-3-27b-it header"
	echo "   URL map priority 1 rule matches header -> forces GKE backend"
	echo "   Bypasses BBR model-based routing entirely"
	echo "================================================================"
	PAYLOAD='{
	  "model": "'"$MODEL_ID"'",
	  "messages": [{"role": "user", "content": "What is Kubernetes?"}]
	}'
	send_request "/v1/chat/completions" "$PAYLOAD" -H "X-Backend-Type: gemma-3-27b-it"
	echo -e "\n"

fi
