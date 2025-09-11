# steffyd

This repository contains the infrastructure and configuration for my personal digital presence, including my homepage, and Mealie instance.

## Structure

This project is organized by service, with each service having its own Terraform and Ansible configurations.

-   `services/`: Contains the configuration for each individual service.
    -   `homepage/`: Contains all configuration for the personal homepage. See the [service README](./services/homepage/README.md) for local testing instructions.
    -   `mealie/`: The configuration for the Mealie recipe manager instance. See the [service README](./services/mealie/README.md) for deployment instructions.

## Technology Stack

-   **Infrastructure as Code:** Terraform is used to provision all cloud resources, including Cloud Run services, GCS buckets, and Cloud DNS zones.
-   **Configuration Management:** Ansible is used to upload application configuration to GCS buckets.
-   **Cloud Provider:** Google Cloud Platform (GCP)
