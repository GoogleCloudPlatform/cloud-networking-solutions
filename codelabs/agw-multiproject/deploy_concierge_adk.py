#!/usr/bin/env python3
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import argparse
import os
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
import vertexai
import agentplatform
from dotenv import load_dotenv
load_dotenv("burger_agent.env")
load_dotenv("pizza_agent.env")
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

    staging_arg = args.staging_bucket or f"{args.project}-staging"
    staging_bucket_name = staging_arg.removeprefix("gs://")
    staging_bucket_uri = f"gs://{staging_bucket_name}"

    vertexai.init(
        project=args.project,
        location=args.region,
        staging_bucket=staging_bucket_uri,
    )

    print("Cleaning up old unused purchasing concierge deployments...")
    delete_old_deployments(args.project, args.region, ["purchasing-concierge-adk"])

    client = agentplatform.Client(
        project=args.project,
        location=args.region,
        http_options=dict(api_version="v1beta1"),
    )

    from purchasing_concierge.agent import root_agent
    from vertexai.preview import reasoning_engines
    from google.adk.sessions import InMemorySessionService

    adk_app = reasoning_engines.AdkApp(
        agent=root_agent,
        session_service_builder=lambda: InMemorySessionService(),
        enable_tracing=False,
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
                    str_vals = [v for k, v in input.items() if isinstance(v, str) and k not in ("user", "userId", "user_id", "author", "role", "session_id", "sessionId")]
                    if str_vals:
                        input = str_vals[0]
                    else:
                        input = str(input)
                    break

            message = str(input) if input is not None else ""
            effective_user_id = user_id or "console-tester-user"
            effective_session_id = session_id or f"session-{effective_user_id}"

            return message, effective_user_id, effective_session_id, kwargs

        def stream_query(self, input = None, user_id = None, session_id = None, **kwargs):
            message, effective_user_id, effective_session_id, clean_kwargs = self._parse_args(input, user_id, session_id, **kwargs)
            for chunk in self.app.stream_query(message=message, user_id=effective_user_id, session_id=effective_session_id, **clean_kwargs):
                if isinstance(chunk, dict) and isinstance(chunk.get("content"), dict):
                    parts = chunk["content"].get("parts", [])
                    if isinstance(parts, list):
                        for part in parts:
                            if isinstance(part, dict) and "text" in part:
                                if not part.get("thought") and not part.get("raw_thought"):
                                    text_val = part["text"]
                                    if text_val:
                                        yield {
                                            "output": text_val,
                                            "text": text_val,
                                            "content": {
                                                "parts": [{"text": text_val}],
                                                "role": "model"
                                            }
                                        }
                elif isinstance(chunk, str) and chunk:
                    yield {
                        "output": chunk,
                        "text": chunk,
                        "content": {
                            "parts": [{"text": chunk}],
                            "role": "model"
                        }
                    }

        def query(self, input = None, user_id = None, session_id = None, **kwargs) -> dict:
            final_text = ""
            for item in self.stream_query(input=input, user_id=user_id, session_id=session_id, **kwargs):
                if isinstance(item, dict) and "output" in item:
                    final_text += item["output"]
                elif isinstance(item, str):
                    final_text += item
            return {
                "output": final_text,
                "text": final_text,
                "content": {
                    "parts": [{"text": final_text}],
                    "role": "model"
                }
            }

        async def async_query(self, input = None, user_id = None, session_id = None, **kwargs) -> dict:
            return self.query(input=input, user_id=user_id, session_id=session_id, **kwargs)

        async def async_stream_query(self, input = None, user_id = None, session_id = None, **kwargs):
            for chunk in self.stream_query(input=input, user_id=user_id, session_id=session_id, **kwargs):
                yield chunk

    playground_app = PlaygroundCompatibleAdkAgent(app=adk_app)

    load_dotenv("burger_agent.env")
    load_dotenv("pizza_agent.env")

    raw_env_vars = {
        "GOOGLE_GENAI_USE_VERTEXAI": "true",
        "AGENT_PROJECT_ID": args.project,
        "AGENT_REGION": args.region,
        "GOVERNANCE_PROJECT_ID": gateway_project,
        "PIZZA_SELLER_AGENT_ID": os.environ.get("PIZZA_SELLER_AGENT_ID", ""),
        "BURGER_SELLER_AGENT_ID": os.environ.get("BURGER_SELLER_AGENT_ID", ""),
    }
    filtered_env_vars = {k: v for k, v in raw_env_vars.items() if v}

    concierge_config = {
        "staging_bucket": staging_bucket_uri,
        "gcs_dir_name": "concierge_agent",
        "display_name": "purchasing-concierge-adk",
        "requirements": [
            "google-cloud-aiplatform[agent_engines]>=1.149.0",
            "google-adk[a2a,agent-identity]==1.34.0",
            "httpx>=0.28.1",
            "requests>=2.32.0",
            "cloudpickle",
            "pydantic",
            "google-genai",
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
        "env_vars": filtered_env_vars,
    }

    print("Deploying Purchasing Concierge with Agent Identity & Agent Gateway...")
    deployed_concierge = client.agent_engines.create(
        agent=playground_app,
        config=concierge_config,
    )
    concierge_name = deployed_concierge.api_resource.name
    print(f"Purchasing Concierge deployed: {concierge_name}")
    print(f"Concierge ID: {concierge_name}")

    with open("concierge_agent.env", "w") as f:
        f.write(f"CONCIERGE_AGENT_ID={concierge_name}\n")
    print("Saved concierge agent ID to concierge_agent.env")

if __name__ == "__main__":
    main()
