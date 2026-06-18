# Version: 12
# Added command line flags to selectively filter or generate endpoints:
# - --region: Regional location (e.g. us-central1). Default: us-central1 (or fallbacks).
# - --multi-region: Multi-region location to include (e.g. us, eu, or none). Default: none.
#   Note: Multi-region endpoints (e.g. us-*) are registered in the "global" registry location 
#   because the Agent Registry API does not support multi-region codes in --location.
# - --mtls-endpoints: choices=["include", "exclude"], default="exclude".
# - --clear-all: Bulk deregister all currently registered services.
# - --dry-run: Run without invoking actual gcloud registry changes.
# - --project: Target GCP Project.
#
# Path Resolution:
# - Dynamically resolves the path of "googleapis.txt" relative to the script's directory
#   so the script can be executed from any working directory (e.g., project root).
#
# Smart Skipping:
# - Fetches already registered endpoints at startup and automatically skips them, 
#   avoiding any ALREADY_EXISTS CLI errors.
#
# Smart Suffixing & Regional Prefix Alignment:
# - The regional Agent Gateway in "{region}" resolves endpoints by querying the local regional registry
#   partition for a service ID prefixed with the region name (e.g. us-central1-cloudresourcemanager-mtls).
# - Therefore, when registering in a regional partition, the script automatically prepends the "{region}-"
#   prefix to the derived resource ID (if not already present).
# - When registering in the "global" partition, natural names are used (e.g. cloudresourcemanager-mtls).
# - Only if the final derived name is too short (< 6 characters, e.g., "iap" or "trace") do we append 
#   "-api" (e.g. "iap-api", "trace-api") to satisfy the backend's 6-character minimum length constraint.
#
# Cross-Registry Registration & Collision Prevention:
# - Global and multi-region endpoints are cross-registered in both the "global" and "{region}" registries.
# - Regional and regionalized locational endpoints are registered ONLY in the "{region}" registry partition.
# - De-duplication maps hostnames by (derived_resource_name, registry_location) to prevent Spanner key 
#   collisions when global and regional variants derive to the same Service ID (e.g., us-central1-discoveryengine-mtls).

import argparse
import json
import os
import re
import subprocess
import sys

def get_gcloud_config(prop):
    try:
        result = subprocess.run(
            ["gcloud", "config", "get-value", prop],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None

def list_registered_services(project, location):
    """Lists all currently registered services in the registry."""
    cmd = [
        "gcloud",
        "alpha",
        "agent-registry",
        "services",
        "list",
        f"--project={project}",
        f"--location={location}",
        "--format=json"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error listing services in location {location}: {e.stderr}", file=sys.stderr)
        return []

def delete_service(service_id, project, location, dry_run=False):
    """Deletes a service from the registry."""
    cmd = [
        "gcloud",
        "alpha",
        "agent-registry",
        "services",
        "delete",
        service_id,
        f"--project={project}",
        f"--location={location}",
        "--quiet"
    ]
    print(f"{'[DRY RUN] ' if dry_run else ''}Running: {' '.join(cmd)}")
    if dry_run:
        return True
    try:
        subprocess.run(cmd, check=True)
        print(f"Successfully deleted service {service_id} in {location}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error deleting service {service_id} in {location}: {e}", file=sys.stderr)
        return False

def parse_googleapis_txt(file_path):
    """Parses googleapis.txt into categorized services based on new taxonomy."""
    categories = {
        "global_and_locational_all": [],
        "global_and_locational_region_only": [],
        "global": [],
        "regional_only": []
    }
    
    if not os.path.exists(file_path):
        print(f"Error: File {file_path} not found.")
        sys.exit(1)
        
    current_category = None
    with open(file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            # Detect category based on comment section headings
            if line.startswith("#"):
                comment_content = line.lstrip("#").strip().lower()
                if "global and locational (by region & multi-region)" in comment_content:
                    current_category = "global_and_locational_all"
                elif "global and locational (by region only)" in comment_content:
                    current_category = "global_and_locational_region_only"
                elif "global endpoints" in comment_content:
                    current_category = "global"
                elif "regional endpoints" in comment_content:
                    current_category = "regional_only"
                continue
                
            # Add base hostname to the active category if it contains .googleapis.com or similar format
            if current_category and (".googleapis.com" in line or line.endswith(".com")):
                categories[current_category].append(line)
                
    return categories

def derive_resource_name(hostname, location, region_prefix=None):
    """Derives the standardized registry resource name for a given hostname and registry location."""
    name = hostname
    if name.endswith(".googleapis.com"):
        name = name[: -len(".googleapis.com")]
    name = name.replace(".", "-")
    
    # Align service_id with regional gateway discovery expected lookup ID
    if location != "global" and region_prefix:
        # Prepend region prefix if not already present
        if not name.startswith(f"{region_prefix}-"):
            name = f"{region_prefix}-{name}"
            
    # Apply Smart Suffixing if the final name is too short (< 6 characters)
    if len(name) < 6:
        name = f"{name}-api"
        
    return name

def main():
    parser = argparse.ArgumentParser(
        description="Register Google API endpoints in the Vertex AI Agent Registry using cross-registry registration.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("REGION") or "us-central1",
        help="Region to use for regional endpoint URL generation, registry partition, and policy targeting."
    )
    parser.add_argument(
        "--multi-region",
        default="none",
        help="Multi-region location to include (e.g. us, eu, or none)."
    )
    parser.add_argument(
        "--mtls-endpoints",
        choices=["include", "exclude"],
        default="exclude",
        help="Whether to include or exclude mTLS endpoints."
    )
    parser.add_argument(
        "--clear-all",
        action="store_true",
        help="Deregister/delete all registered services from active registry locations and exit."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions/commands without executing them."
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("PROJ_ID") or get_gcloud_config("project"),
        help="Google Cloud Project ID."
    )
    
    args = parser.parse_args()
    
    if args.clear_all:
        if args.multi_region != "none" or args.mtls_endpoints != "exclude":
            print("Error: --clear-all cannot be combined with endpoint filtering flags (--multi-region, --mtls-endpoints).")
            sys.exit(1)
            
    if not args.project:
        print("Error: Project ID not set and could not be determined from environment/gcloud config.")
        sys.exit(1)
        
    print(f"Using Project: {args.project}")
    
    # --- Clear All Logic (Multi-Location Aware) ---
    if args.clear_all:
        locations_to_clear = ["global"]
        if args.region and args.region.lower() != "none":
            locations_to_clear.append(args.region)
            
        locations_to_clear = sorted(list(set(locations_to_clear)))
        
        print(f"\nListing registered services to clear in active locations: {', '.join(locations_to_clear)}...")
        total_services_found = 0
        success_count = 0
        
        for loc in locations_to_clear:
            print(f"\nScanning location: {loc}...")
            services = list_registered_services(args.project, loc)
            if not services:
                print(f"No services found in location {loc}.")
                continue
                
            total_services_found += len(services)
            print(f"Found {len(services)} services in {loc}. Starting deletion...")
            for svc in services:
                service_path = svc.get("name", "")
                if not service_path:
                    continue
                service_id = service_path.split("/")[-1]
                if delete_service(service_id, args.project, loc, dry_run=args.dry_run):
                    success_count += 1
                    
        print(f"\nCleared {success_count}/{total_services_found} services successfully.")
        sys.exit(0)
        
    # --- Cross-Registry Endpoint Generation ---
    script_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(script_dir, "googleapis.txt")
    categories = parse_googleapis_txt(file_path)
    
    # Dictionary mapping (derived_resource_name, registry_location) -> hostname
    # This automatically de-duplicates collisions where global and regional variants derive to the same ID.
    endpoints_map = {}
    
    def add_endpoint(hostname, loc):
        res_name = derive_resource_name(hostname, loc, args.region)
        key = (res_name, loc)
        if key in endpoints_map:
            # If collision occurs, regionalized hostname is more specific, so overwrite/prefer it
            if hostname.startswith(f"{args.region}-"):
                endpoints_map[key] = hostname
        else:
            endpoints_map[key] = hostname
            
    # 1. Process global endpoints -> Cross-register in global AND regional registries
    for base in categories["global"]:
        add_endpoint(base, "global")
        if args.mtls_endpoints == "include":
            add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), "global")
            
        if args.region and args.region.lower() != "none":
            r_loc = args.region
            add_endpoint(base, r_loc)
            if args.mtls_endpoints == "include":
                add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
            
    # 2. Process global and locational (by region only) endpoints
    for base in categories["global_and_locational_region_only"]:
        # Global variants -> Cross-register in global AND regional registries
        add_endpoint(base, "global")
        if args.mtls_endpoints == "include":
            add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), "global")
            
        if args.region and args.region.lower() != "none":
            r_loc = args.region
            add_endpoint(base, r_loc)
            if args.mtls_endpoints == "include":
                add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
                
            # Regional variants ({region}-{service}) -> Register in regional registry ONLY
            reg_host = f"{r_loc}-{base}"
            add_endpoint(reg_host, r_loc)
            if args.mtls_endpoints == "include":
                add_endpoint(reg_host.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
                
    # 3. Process global and locational (by region & multi-region) endpoints
    for base in categories["global_and_locational_all"]:
        # Global variants -> Cross-register in global AND regional registries
        add_endpoint(base, "global")
        if args.mtls_endpoints == "include":
            add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), "global")
            
        if args.region and args.region.lower() != "none":
            r_loc = args.region
            add_endpoint(base, r_loc)
            if args.mtls_endpoints == "include":
                add_endpoint(base.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
                
            # Regional variants ({region}-{service}) -> Register in regional registry ONLY
            reg_host = f"{r_loc}-{base}"
            add_endpoint(reg_host, r_loc)
            if args.mtls_endpoints == "include":
                add_endpoint(reg_host.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
                
        # Multi-region variants ({multi-region}-{service}) -> Cross-register in global AND regional registries
        if args.multi_region and args.multi_region.lower() != "none":
            m_loc = args.multi_region
            mr_host = f"{m_loc}-{base}"
            add_endpoint(mr_host, "global")
            if args.mtls_endpoints == "include":
                add_endpoint(mr_host.replace(".googleapis.com", ".mtls.googleapis.com"), "global")
                
            if args.region and args.region.lower() != "none":
                r_loc = args.region
                add_endpoint(mr_host, r_loc)
                if args.mtls_endpoints == "include":
                    add_endpoint(mr_host.replace(".googleapis.com", ".mtls.googleapis.com"), r_loc)
                    
    # 4. Process strictly regional endpoints -> Register in regional registry ONLY
    if args.region and args.region.lower() != "none":
        r_loc = args.region
        for base in categories["regional_only"]:
            reg_host = base.replace(".googleapis.com", f".{r_loc}.googleapis.com")
            add_endpoint(reg_host, r_loc)
            
            if args.mtls_endpoints == "include":
                reg_host_mtls = base.replace(".googleapis.com", f".{r_loc}.mtls.googleapis.com")
                add_endpoint(reg_host_mtls, r_loc)
                
    if not endpoints_map:
        print("No endpoints matched the specified location/mTLS criteria.")
        sys.exit(0)
        
    # --- Fetch existing services in active locations for Smart Skipping ---
    unique_target_locations = sorted(list(set(loc for res_name, loc in endpoints_map.keys())))
    existing_services_by_location = {}
    
    for loc in unique_target_locations:
        print(f"Scanning location '{loc}' for existing registrations to enable smart skipping...")
        services_list = list_registered_services(args.project, loc)
        existing_names = set()
        for svc in services_list:
            svc_path = svc.get("name", "")
            if svc_path:
                existing_names.add(svc_path.split("/")[-1])
        existing_services_by_location[loc] = existing_names
        
    print(f"\nSelected {len(endpoints_map)} endpoints for registration:")
    for (res_name, loc), host in sorted(endpoints_map.items()):
        if res_name in existing_services_by_location.get(loc, set()):
            print(f" - {host} in location '{loc}' (Service ID: {res_name}) -> [Already Registered - Skip]")
        else:
            print(f" - {host} in location '{loc}' (Service ID: {res_name}) -> [New - Will Register]")
        
    # Perform registration with dynamic location routing and smart skipping
    for (resource_name, registry_location), hostname in sorted(endpoints_map.items()):
        # Smart Skip Check
        if resource_name in existing_services_by_location.get(registry_location, set()):
            continue
            
        display_name = hostname
        url = f"https://{hostname}"
        
        print(f"\nRegistering {hostname} as {resource_name} in registry location {registry_location}...")
        cmd = [
            "gcloud",
            "alpha",
            "agent-registry",
            "services",
            "create",
            resource_name,
            f"--project={args.project}",
            f"--location={registry_location}",
            f"--display-name={display_name}",
            "--endpoint-spec-type=no-spec",
            f"--interfaces=url={url},protocolBinding=JSONRPC",
        ]
        
        print(f"{'[DRY RUN] ' if args.dry_run else ''}Running: {' '.join(cmd)}")
        if args.dry_run:
            continue
            
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            print(f"Successfully registered {hostname} in {registry_location}")
            if result.stdout:
                print(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error registering {hostname} in {registry_location}: {e.stderr}", file=sys.stderr)

if __name__ == "__main__":
    main()
