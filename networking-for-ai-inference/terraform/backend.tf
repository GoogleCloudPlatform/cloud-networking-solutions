# Copyright 2025 Google LLC
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

# Backend Configuration
#
# This uses partial backend configuration. Initialize with:
#   terraform init -backend-config="bucket=YOUR_GCS_BUCKET" -backend-config="prefix=YOUR_STATE_PREFIX"
#
# Or create a backend.conf file with:
#   bucket = "your-terraform-state-bucket"
#   prefix = "inference-gateway/terraform"
#
# Then run:
#   terraform init -backend-config=backend.conf
#
# Example backend.conf:
#   bucket = "my-project-terraform-state"
#   prefix = "inference-gateway/prod"
