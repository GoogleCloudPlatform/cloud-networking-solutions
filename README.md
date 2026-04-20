# Cloud Network Solutions

This repo contains supporting code artifacts for Cloud Network Solutions reference architectures, samples and demos.

> [!NOTE]
> The code in this repo is not intended for production use.

# Repository Structure

This repository is organized into the following main directories:

## [Reference Architectures](reference-architectures)

Contains complete, end-to-end reference architectures demonstrating best practices for cloud networking solutions.

*   **[Networking for AI Inference](reference-architectures/networking-for-ai-inference)**: Demonstrates how to set up a secure, scalable networking infrastructure for AI inference workloads on Google Cloud, including GKE, Apigee, and Vertex AI.

## [Demos](demos)

Contains smaller, focused demonstrations of specific networking features or integration patterns.

*   **[Service Extensions GKE Gateway](demos/service-extensions-gke-gateway)**: Shows how to use Service Extensions with GKE Gateway to customize traffic management.

# Running samples

Each project within this repo typically holds a self-contained sample, implemented in [Terraform](https://www.terraform.io/).

## Setup

We recommend using [Cloud Shell](https://cloud.google.com/docs/terraform/install-configure-terraform#cloud-shell), which comes pre-configured with Terraform and automatic authentication.

To run a sample:

1.  Clone this repo:
    ```bash
    git clone https://github.com/GoogleCloudPlatform/cloud-networking-solutions
    ```
2.  Navigate to the specific sample directory in `reference-architectures` or `demos`:
    ```bash
    cd cloud-networking-solutions/demos/service-extensions-gke-gateway/terraform/
    ```
3.  Enable any required APIs as defined in the sample's README.
4.  Initialize and view the planned deployed resources:
    ```bash
    terraform init
    terraform plan
    ```
5.  Apply the configuration, entering `yes` at the prompt:
    ```bash
    terraform apply
    ```

> [!NOTE]
> While every effort is taken to ensure the Terraform deploys first time, some resources may take time to become ready for additional configuration. If the first `terraform apply` fails due to resources not existing, wait a few minutes and try again.

Learn more about [Terraform commands](https://cloud.google.com/docs/terraform/basic-commands).

## Cleanup

*   Remove the resources that were created, entering `yes` at the prompt:
    ```bash
    terraform destroy
    ```
# Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information how to get started.

Please note that this project is released with a Contributor Code of Conduct.
By participating in this project you agree to abide by its terms. See [Code of
Conduct](CODE_OF_CONDUCT.md) for more information.

# License

Apache 2.0 - See [LICENSE](LICENSE) for more information.
