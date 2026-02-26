# Guide: Creating a Public Subdomain Zone with NS Delegation

Based on the `dns` module files, specifically the **Prerequisites** section, your current Terraform setup expects the public DNS zone to already exist.

This guide explains how to create that public subdomain zone (e.g., `gateway.example.com`) and set up NS delegation from your top-level domain registrar (e.g., GoDaddy, Namecheap, or another Cloud DNS zone) so it works with your module.

## Objective

Create a dedicated Cloud DNS zone for a subdomain (e.g., `gateway.example.com`) and delegate authority to it from your parent domain (`example.com`). This allows Google Cloud to manage records for that specific subdomain.

---

## Step 1: Create the Managed Zone in Google Cloud

Since the `dns` module uses a `data` source to look up the zone, you must create this zone *before* running your Terraform (or define it in a separate "foundation" Terraform layer).

### Option A: Using `gcloud` CLI (Recommended for one-off setup)

Run the following command to create the zone in your project:

```bash
gcloud dns managed-zones create "inference-gateway-zone" \
    --dns-name="gateway.example.com." \
    --description="Public zone for Inference Gateway" \
    --visibility="public" \
    --project="YOUR_PROJECT_ID"
```

- **Note**: The `--dns-name` must end with a dot (`.`).

### Option B: Using Terraform (Managed Resource)

If you want to manage this zone with Terraform, add this resource to a separate setup file (do not add it inside the `dns` module itself, as that module is designed to *read* the zone):

```hcl
resource "google_dns_managed_zone" "public_zone" {
  name        = "inference-gateway-zone"
  dns_name    = "gateway.example.com."
  description = "Public zone for Inference Gateway"
  visibility  = "public"
}
```

---

## Step 2: Retrieve Assigned Name Servers

Once the zone is created, Google Cloud assigns a set of Name Servers (NS) specific to that zone. You need these for the delegation.

**Command:**

```bash
gcloud dns managed-zones describe inference-gateway-zone --format="value(nameServers)"
```

**Output Example:**

```text
ns-cloud-a1.googledomains.com.
ns-cloud-b1.googledomains.com.
ns-cloud-c1.googledomains.com.
ns-cloud-d1.googledomains.com.
```

*Copy this list. You will need it for the next step.*

---

## Step 3: Configure NS Delegation at Your Registrar

You must now tell the rest of the internet that `gateway.example.com` is managed by Google Cloud. You do this at the registrar where you bought your top-level domain (e.g., `example.com`).

1. **Log in** to your domain registrar (e.g., Namecheap, GoDaddy, AWS Route53, or Google Domains).
2. Navigate to the **DNS Management** settings for your domain (`example.com`).
3. Add a new **NS (Name Server)** record for the subdomain.
   - **Host/Name**: `gateway` (or whatever subdomain prefix you chose).
   - **Value/Target**: Enter the first name server from Step 2 (e.g., `ns-cloud-a1.googledomains.com.`).
   - **TTL**: Default (usually 3600 or 1 hour).
4. **Repeat** this for *all four* name servers provided by Google Cloud. You should have 4 separate NS records for the `gateway` host.

---

## Step 4: Verify Propagation

DNS propagation can take time (minutes to hours). You can verify it using `dig`:

```bash
dig NS gateway.example.com +short
```

If it returns the Google Cloud name servers, the delegation is working.

---

## Integration with the Terraform DNS Module

Once NS delegation is configured and propagation is complete, the Terraform [dns module](../terraform/modules/dns/README.md) manages DNS records within this zone automatically.

The `dns` module expects the zone to already exist and uses a `data` source to look it up. Configure the following variables in your `terraform.tfvars`:

```hcl
# The domain must end with a dot
dns_zone_domain = "gateway.example.com."
```

The module will then create DNS records (A records, CNAME records) for your gateway endpoints based on the gateway configuration. For example:

- `smg.gateway.example.com` -- Self Managed Inference Gateway endpoint
- `inference.gateway.example.com` -- GKE Inference Gateway endpoint
- `api.gateway.example.com` -- Apigee API endpoint (if semantic caching is enabled)

Refer to the [dns module README](../terraform/modules/dns/README.md) for the full list of supported variables and outputs.
