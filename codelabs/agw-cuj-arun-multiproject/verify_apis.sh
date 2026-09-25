#!/bin/bash
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

REQUIRED_APIS=(
	"agentregistry.googleapis.com"
	"aiplatform.googleapis.com"
	"apphub.googleapis.com"
	"apptopology.googleapis.com"
	"cloudapiregistry.googleapis.com"
	"cloudtrace.googleapis.com"
	"compute.googleapis.com"
	"dataform.googleapis.com"
	"iam.googleapis.com"
	"iamconnectors.googleapis.com"
	"iap.googleapis.com"
	"logging.googleapis.com"
	"modelarmor.googleapis.com"
	"monitoring.googleapis.com"
	"networksecurity.googleapis.com"
	"networkservices.googleapis.com"
	"notebooks.googleapis.com"
	"observability.googleapis.com"
	"securitycenter.googleapis.com"
	"saasservicemgmt.googleapis.com"
	"storage.googleapis.com"
	"telemetry.googleapis.com"
	"texttospeech.googleapis.com"
	"artifactregistry.googleapis.com"
	"cloudbuild.googleapis.com"
	"cloudresourcemanager.googleapis.com"
	"iamcredentials.googleapis.com"
	"serviceusage.googleapis.com"
	"run.googleapis.com"
)

if [ -z "$PROJECT_GOVERNANCE" ] || [ -z "$PROJECT_CONCIERGE" ] || [ -z "$PROJECT_SELLERS" ]; then
	echo "Error: PROJECT_GOVERNANCE, PROJECT_CONCIERGE, and PROJECT_SELLERS environment variables must be set."
	exit 1
fi

PROJECTS=("$PROJECT_GOVERNANCE" "$PROJECT_CONCIERGE" "$PROJECT_SELLERS")
LABELS=("GOVERNANCE" "CONCIERGE" "SELLERS")

printf "\n%-36s | %-12s | %-12s | %-12s\n" "API Name" "${LABELS[0]}" "${LABELS[1]}" "${LABELS[2]}"
printf "%s\n" "------------------------------------------------------------------------------"

ALL_SYNCED=true

declare -A ENABLED_GOV
declare -A ENABLED_CON
declare -A ENABLED_SEL

for s in $(gcloud services list --enabled --project="${PROJECTS[0]}" --format="value(config.name)"); do
	ENABLED_GOV["$s"]=1
done

for s in $(gcloud services list --enabled --project="${PROJECTS[1]}" --format="value(config.name)"); do
	ENABLED_CON["$s"]=1
done

for s in $(gcloud services list --enabled --project="${PROJECTS[2]}" --format="value(config.name)"); do
	ENABLED_SEL["$s"]=1
done

for api in "${REQUIRED_APIS[@]}"; do
	[ "${ENABLED_GOV[$api]}" = "1" ] && s0="ENABLED" || s0="MISSING"
	[ "${ENABLED_CON[$api]}" = "1" ] && s1="ENABLED" || s1="MISSING"
	[ "${ENABLED_SEL[$api]}" = "1" ] && s2="ENABLED" || s2="MISSING"

	if [ "$s0" = "MISSING" ] || [ "$s1" = "MISSING" ] || [ "$s2" = "MISSING" ]; then
		ALL_SYNCED=false
	fi

	printf "%-36s | %-12s | %-12s | %-12s\n" "$api" "$s0" "$s1" "$s2"
done

printf "%s\n" "------------------------------------------------------------------------------"

if [ "$ALL_SYNCED" = true ]; then
	echo "✅ All 29 required APIs are ENABLED and synchronized across all three projects."
	echo ""
	exit 0
else
	echo "❌ Discrepancies detected across projects. Please run API enablement for missing services."
	echo ""
	exit 1
fi
