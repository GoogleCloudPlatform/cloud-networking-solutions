#!/usr/bin/env python3
import os
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
from google.cloud.aiplatform_v1 import ReasoningEngineServiceClient, DeleteReasoningEngineRequest

def delete_old_deployments(project: str, region: str, keep_latest: bool = False, target_display_names: list[str] = None):
    client = ReasoningEngineServiceClient(client_options={"api_endpoint": f"{region}-aiplatform.googleapis.com"})
    parent = f"projects/{project}/locations/{region}"

    try:
        response = client.list_reasoning_engines(parent=parent)
        engines = list(response.reasoning_engines)
        
        # Sort engines by create_time descending (newest first)
        engines.sort(key=lambda x: x.create_time, reverse=True)
        
        seen = set()
        for eng in engines:
            if target_display_names and eng.display_name not in target_display_names:
                print(f"Skipping unrecognized reasoning engine: {eng.name} ({eng.display_name})")
                continue

            if keep_latest:
                if eng.display_name not in seen:
                    print(f"Keeping latest deployment for {eng.display_name}: {eng.name}")
                    seen.add(eng.display_name)
                    continue
                else:
                    print(f"Deleting older duplicate deployment: {eng.name} ({eng.display_name})")
            else:
                print(f"Deleting deployment: {eng.name} ({eng.display_name})")
            
            try:
                op = client.delete_reasoning_engine(request=DeleteReasoningEngineRequest(name=eng.name, force=True))
                op.result()
                print(f"Successfully deleted {eng.name}")
            except Exception as e:
                print(f"Failed to delete {eng.name}: {e}")
    except Exception as e:
                print(f"Error listing reasoning engines for cleanup: {e}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Cleanup unused Reasoning Engines")
    parser.add_argument("--project", required=True, help="Google Cloud Project ID")
    parser.add_argument("--region", required=True, help="Google Cloud Region")
    parser.add_argument("--keep-latest", action="store_true", help="Keep the latest deployment for each agent type and only delete older duplicates")
    args = parser.parse_args()
    
    target_names = ["burger-seller-agent-adk", "pizza-seller-agent-adk", "purchasing-concierge-adk"]
    delete_old_deployments(args.project, args.region, keep_latest=args.keep_latest, target_display_names=target_names)

