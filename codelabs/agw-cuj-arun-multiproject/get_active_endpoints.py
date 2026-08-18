#!/usr/init/env python3
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
import os
import argparse
import os
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
import vertexai
from vertexai.preview import reasoning_engines

def main():
    parser = argparse.ArgumentParser(description="Dynamically resolve deployed Reasoning Engine IDs")
    parser.add_argument("--project", default=os.getenv("PROJECT_ID", "deepakmichael-svc3"), help="GCP Project ID")
    parser.add_argument("--region", default=os.getenv("REGION", "us-central1"), help="GCP Region")
    args = parser.parse_args()

    vertexai.init(project=args.project, location=args.region)

    print(f"Fetching deployed reasoning engines for project {args.project} ({args.region})...\n")
    try:
        engines = reasoning_engines.ReasoningEngine.list()
        engines = sorted(engines, key=lambda e: getattr(e, 'create_time', None) or '', reverse=True)

        concierge_id = None
        burger_id = None
        pizza_id = None

        for e in engines:
            name = e.resource_name.split("/")[-1]
            if not concierge_id and e.display_name == "purchasing-concierge-adk":
                concierge_id = name
            elif not burger_id and e.display_name == "burger-seller-agent-adk":
                burger_id = name
            elif not pizza_id and e.display_name == "pizza-seller-agent-adk":
                pizza_id = name

        print("Copy and paste the following export commands:")
        print("---------------------------------------------")
        print(f"export CONCIERGE_ENGINE_ID=\"{concierge_id or 'NOT_FOUND'}\"")
        print(f"export BURGER_ENGINE_ID=\"{burger_id or 'NOT_FOUND'}\"")
        print(f"export PIZZA_ENGINE_ID=\"{pizza_id or 'NOT_FOUND'}\"")
        print("---------------------------------------------")

    except Exception as e:
        print(f"Error listing reasoning engines: {e}")

if __name__ == "__main__":
    main()
