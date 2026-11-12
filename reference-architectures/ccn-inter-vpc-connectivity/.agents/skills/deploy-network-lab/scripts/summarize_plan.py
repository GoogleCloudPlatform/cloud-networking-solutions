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

import json
import sys
from collections import defaultdict

def summarize_plan(json_path):
    try:
        with open(json_path, 'r') as f:
            plan_data = json.load(f)
    except Exception as e:
        print(f"Error reading or parsing {json_path}: {e}")
        sys.exit(1)

    resource_changes = plan_data.get('resource_changes', [])

    if not resource_changes:
        print("No resource changes found in the plan.")
        return

    summary = defaultdict(lambda: defaultdict(int))
    total_by_action = defaultdict(int)
    destructive_addresses = []

    for change in resource_changes:
        resource_type = change.get('type')
        address = change.get('address', resource_type)
        actions = change.get('change', {}).get('actions', [])

        action_type = "no-op"
        if "create" in actions and "delete" in actions:
            action_type = "replace"
            destructive_addresses.append((action_type, address))
        elif "create" in actions:
            action_type = "create"
        elif "update" in actions:
            action_type = "update"
        elif "delete" in actions:
            action_type = "delete"
            destructive_addresses.append((action_type, address))
        elif "read" in actions:
            action_type = "read"

        if action_type != "no-op" and action_type != "read":
            summary[resource_type][action_type] += 1
            total_by_action[action_type] += 1

    print("Resource Change Summary:")
    print("=========================")
    for res_type, actions_dict in sorted(summary.items()):
        actions_str = ", ".join([f"{act}: {count}" for act, count in sorted(actions_dict.items())])
        print(f"{res_type} -> {actions_str}")

    print("=========================")
    print("Total Changes:")
    for action, count in sorted(total_by_action.items()):
        print(f"  {action.capitalize()}: {count}")
    print(f"  Total planned changes: {sum(total_by_action.values())}")
    if destructive_addresses:
        print("=========================")
        print("WARNING - Destructive Changes (Delete / Replace):")
        for act, addr in destructive_addresses:
            print(f"  [{act.upper()}] {addr}")
    print("=========================")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python summarize_plan.py <path_to_plan_json>")
        sys.exit(1)

    summarize_plan(sys.argv[1])
