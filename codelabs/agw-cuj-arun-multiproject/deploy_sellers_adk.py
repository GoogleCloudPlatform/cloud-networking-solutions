#!/usr/bin/env python3
import argparse
import os
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
import vertexai
from dotenv import load_dotenv
from cleanup_old_deployments import delete_old_deployments

load_dotenv()

def main():
    parser = argparse.ArgumentParser(description="Deploy Remote Seller Agents with Agent Identity and Agent Gateway")
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

    print("Cleaning up old unused seller agent deployments...")
    delete_old_deployments(args.project, args.region, ["burger-seller-agent-adk", "pizza-seller-agent-adk", "purchasing-concierge-adk"])

    client = vertexai.Client(
        project=args.project,
        location=args.region,
        http_options=dict(api_version="v1beta1"),
    )

    from remote_seller_agents.burger_agent.agent_adk import burger_agent as burger_adk_agent
    from remote_seller_agents.pizza_agent.agent_adk import pizza_agent as pizza_adk_agent
    from vertexai.preview import reasoning_engines

    class PlaygroundCompatibleAdkAgent:
        agent_framework = "google-adk"

        def __init__(self, app):
            self.app = app

        def set_up(self):
            if hasattr(self.app, "set_up"):
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

    common_config = {
        "staging_bucket": staging_bucket,
        "requirements": [
            "google-cloud-aiplatform[agent_engines]>=1.149.0",
            "google-adk[a2a,agent-identity]==1.34.0",
        ],
        "extra_packages": ["./remote_seller_agents"],
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
        }
    }

    # Deploy Burger Agent
    print("Deploying Burger Agent with Agent Identity & Agent Gateway...")
    burger_app = reasoning_engines.AdkApp(agent=burger_adk_agent, enable_tracing=False)
    burger_playground = PlaygroundCompatibleAdkAgent(burger_app)
    burger_config = {**common_config, "display_name": "burger-seller-agent-adk"}
    deployed_burger = client.agent_engines.create(agent=burger_playground, config=burger_config)
    burger_name = deployed_burger.api_resource.name
    print(f"Burger Agent deployed: {burger_name}")

    # Deploy Pizza Agent
    print("Deploying Pizza Agent with Agent Identity & Agent Gateway...")
    pizza_app = reasoning_engines.AdkApp(agent=pizza_adk_agent, enable_tracing=False)
    pizza_playground = PlaygroundCompatibleAdkAgent(pizza_app)
    pizza_config = {**common_config, "display_name": "pizza-seller-agent-adk"}
    deployed_pizza = client.agent_engines.create(agent=pizza_playground, config=pizza_config)
    pizza_name = deployed_pizza.api_resource.name
    print(f"Pizza Agent deployed: {pizza_name}")

    with open("seller_agents.env", "w") as f:
        f.write(f"BURGER_SELLER_AGENT_ID={burger_name}\n")
        f.write(f"PIZZA_SELLER_AGENT_ID={pizza_name}\n")
    print("Saved agent IDs to seller_agents.env")

if __name__ == "__main__":
    main()
