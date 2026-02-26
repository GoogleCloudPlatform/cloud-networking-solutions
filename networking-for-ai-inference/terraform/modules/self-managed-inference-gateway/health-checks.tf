/**
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# ==============================================================================
# HEALTH CHECK RESOURCES
# ==============================================================================
#
# Health checks are now created dynamically in backends.tf for backends
# that specify a health_check configuration. This file is kept for reference
# and for any global health check needs.
#
# Backend-specific health checks are defined as:
#   google_compute_region_health_check.backends["backend-name"]
#
# Backends that don't need health checks (Internet NEG, Serverless NEG):
#   - Set health_check = null in the backend configuration
#
# ==============================================================================

# Note: All regional health checks are now created in backends.tf using
# the flexible for_each pattern based on var.backends.services configuration.
