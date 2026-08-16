#!/usr/bin/env python3
import argparse
import os
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
import vertexai
from dotenv import load_dotenv

load_dotenv("seller_agents.env")
load_dotenv()
from cleanup_old_deployments import delete_old_deployments

def main():
    parser = argparse.ArgumentParser(description="Deploy Purchasing Concierge with Agent Identity and Agent Gateway")
    parser.add_argument("--project", required=True, help="Google Cloud Project ID")
    parser.add_argument("--region", required=True, help="Google Cloud Region")
    parser.add_argument("--staging-bucket", help="GCS bucket for staging")
    parser.add_argument("--gateway-name", required=True, help="Agent Gateway name")
    parser.add_argument("--gateway-project", help="Agent Gateway project ID (defaults to --project)")
    args = parser.parse_args()

    gateway_project = args.gateway_project or args.project

    staging_bucket = args.staging_bucket or f"gs://{args.project}-staging"
    if not staging_bucket.startswith("gs://"):
        staging_bucket = f"gs://{staging_bucket}"

    vertexai.init(
        project=args.project,
        location=args.region,
        staging_bucket=staging_bucket,
    )

    print("Cleaning up old unused purchasing concierge deployments...")
    delete_old_deployments(args.project, args.region, ["purchasing-concierge-adk"])

    client = vertexai.Client(
        project=args.project,
        location=args.region,
        http_options=dict(api_version="v1beta1"),
    )

    from purchasing_concierge.agent import root_agent
    from vertexai.preview import reasoning_engines

    adk_app = reasoning_engines.AdkApp(
        agent=root_agent,
        enable_tracing=False,
        env_vars={
            "GOOGLE_GENAI_USE_VERTEXAI": "true",
            "PIZZA_SELLER_AGENT_ID": os.environ.get("PIZZA_SELLER_AGENT_ID", ""),
            "BURGER_SELLER_AGENT_ID": os.environ.get("BURGER_SELLER_AGENT_ID", ""),
        }
    )

    class PlaygroundCompatibleAdkAgent:
        agent_framework = "google-adk"

        def __init__(self, app):
            self.app = app

        def set_up(self):
            self.app.set_up()

        def register_operations(self) -> dict[str, list[str]]:
            return {
                "": ["query", "async_query"],
                "stream": ["stream_query", "async_stream_query"],
            }

        def _parse_args(self, input = None, user_id = None, session_id = None, **kwargs):
            kw_user_id = kwargs.pop("user_id", None)
            kw_userId = kwargs.pop("userId", None)
            user_id = user_id or kw_user_id or kw_userId

            kw_session_id = kwargs.pop("session_id", None)
            kw_sessionId = kwargs.pop("sessionId", None)
            session_id = session_id or kw_session_id or kw_sessionId

            kw_message = kwargs.pop("message", None)
            kw_input = kwargs.pop("input", None)
            if input is None:
                input = kw_message or kw_input

            if input is None:
                 raise ValueError("Either 'input' or 'message' must be provided")

            while isinstance(input, dict):
                user_id = user_id or input.get("user_id") or input.get("userId")
                session_id = session_id or input.get("session_id") or input.get("sessionId")
                
                next_val = input.get("message")
                if next_val is None:
                    next_val = input.get("input")
                if next_val is None:
                    next_val = input.get("prompt")
                if next_val is None:
                    next_val = input.get("text")
                
                if next_val is not None:
                    input = next_val
                else:
                    str_vals = [v for v in input.values() if isinstance(v, str)]
                    if str_vals:
                        input = str_vals[0]
                    else:
                        input = str(input)
                    break

            message = str(input) if input is not None else ""
            effective_user_id = user_id or "console-tester-user"
            effective_session_id = session_id
                
            return message, effective_user_id, effective_session_id, kwargs

        def query(self, input = None, user_id = None, session_id = None, **kwargs) -> dict:
            message, effective_user_id, effective_session_id, clean_kwargs = self._parse_args(input, user_id, session_id, **kwargs)
            final_text = ""
            for chunk in self.app.stream_query(message=message, user_id=effective_user_id, session_id=effective_session_id, **clean_kwargs):
                if isinstance(chunk, dict) and isinstance(chunk.get("content"), dict):
                    parts = chunk["content"].get("parts", [])
                    if isinstance(parts, list):
                        for part in parts:
                            if isinstance(part, dict) and "text" in part:
                                if not part.get("thought") and not part.get("raw_thought"):
                                    final_text += part["text"]
            return {"output": final_text}

        def stream_query(self, input = None, user_id = None, session_id = None, **kwargs):
            message, effective_user_id, effective_session_id, clean_kwargs = self._parse_args(input, user_id, session_id, **kwargs)
            for chunk in self.app.stream_query(message=message, user_id=effective_user_id, session_id=effective_session_id, **clean_kwargs):
                yield chunk

        async def async_query(self, input = None, user_id = None, session_id = None, **kwargs) -> dict:
            return self.query(input=input, user_id=user_id, session_id=session_id, **kwargs)

        async def async_stream_query(self, input = None, user_id = None, session_id = None, **kwargs):
            for chunk in self.stream_query(input=input, user_id=user_id, session_id=session_id, **kwargs):
                yield chunk

    playground_app = PlaygroundCompatibleAdkAgent(app=adk_app)

    concierge_config = {
        "staging_bucket": staging_bucket,
        "display_name": "purchasing-concierge-adk",
        "requirements": [
            "google-cloud-aiplatform[agent_engines]>=1.149.0",
            "google-adk[a2a,agent-identity]==1.34.0",
            "cloudpickle",
            "pydantic",
        ],
        "extra_packages": [
            "./purchasing_concierge",
        ],
        "identity_type": "AGENT_IDENTITY",
        "agent_gateway_config": {
            "agent_to_anywhere_config": {
                "agent_gateway": f"projects/{gateway_project}/locations/{args.region}/agentGateways/{args.gateway_name}"
            }
        },
        "env_vars": {
            "GOOGLE_GENAI_USE_VERTEXAI": "true",
            "AGENT_PROJECT_ID": args.project,
            "AGENT_REGION": args.region,
            "GOVERNANCE_PROJECT_ID": gateway_project,
            "PIZZA_SELLER_AGENT_ID": os.environ.get("PIZZA_SELLER_AGENT_ID", ""),
            "BURGER_SELLER_AGENT_ID": os.environ.get("BURGER_SELLER_AGENT_ID", ""),
        },
    }

    print("Deploying Purchasing Concierge with Agent Identity & Agent Gateway...")
    deployed_concierge = client.agent_engines.create(
        agent=playground_app,
        config=concierge_config,
    )
    concierge_name = deployed_concierge.api_resource.name
    print(f"Purchasing Concierge deployed: {concierge_name}")
    print(f"Concierge ID: {concierge_name}")

if __name__ == "__main__":
    main()
