# Gemini Project Analysis: steffyd

## Project Overview

This project, "steffyd," is intended to manage the infrastructure and configuration for a personal digital presence within the Google Cloud project `steffyd`. It will be hosted as a GitHub repository. The project is designed to be managed using a combination of Terraform for infrastructure provisioning and Ansible for configuration management, with a clear, service-oriented directory structure.

## Core Components

*   **Homepage:** A personal homepage/dashboard with OAuth2-proxy sidecar for authentication.
*   **Mealie:** A self-hosted recipe manager instance.
*   **Regional Load Balancer:** A regional load balancer that routes traffic to the homepage service.

## Architecture and Technology

*   **Directory Structure:** The project is organized into `services/` and `components/` directories.
    *   `services/`: Contains the configuration for each individual service (`homepage`, `mealie`). Each service directory contains its own `terraform/` and `ansible/` subdirectories where applicable.
    *   `components/`: Contains shared infrastructure components, such as the `regional-load-balancer`.
*   **Homepage Service (with OAuth2-proxy sidecar):**
    *   **Architecture:** Uses a sidecar pattern with two containers in a single Cloud Run service:
        - **OAuth2-proxy sidecar** (port 4180): Handles Google OAuth authentication
        - **Homepage container** (port 3000): Serves the actual homepage content
    *   **Security:** The homepage container is not directly accessible from the internet. All traffic must go through the OAuth2-proxy sidecar.
    *   **Configuration:** Application configuration files (YAML, CSS) are uploaded to a dedicated Google Cloud Storage bucket via an Ansible playbook.
    *   **GCS Upload Workaround:** Due to compatibility issues between the `google.cloud.gcp_storage_object` Ansible module and Python 3.13 (specifically a `TypeError: a bytes-like object is required, not 'str'` originating from the `google-crc32c` library), the Ansible playbook for GCS uploads (`services/homepage/ansible/upload_config.yml`) has been modified to use `gsutil` commands directly via the `ansible.builtin.command` module. This bypasses the problematic Python module.
*   **Regional Load Balancer:**
    *   **Infrastructure:** A regional external HTTP(S) load balancer that routes traffic from a custom domain to the homepage service. It handles SSL termination with a managed certificate.
    *   **Routing:** Routes `steffyd.com` → Homepage Service → OAuth2-proxy sidecar → Homepage container
*   **Infrastructure as Code:** Terraform is the primary tool for provisioning all cloud resources (Cloud Run, GCS, IAM, Regional Load Balancer).
*   **Configuration Management:** Ansible is used for application-level configuration, such as uploading configuration files to GCS.

### Dependencies

To run Ansible playbooks that interact with Google Cloud Storage (specifically `services/homepage/ansible/upload_config.yml`), ensure you have `gsutil` installed and configured. `gsutil` is part of the Google Cloud SDK.

## My Role

My primary role is to assist in the development and management of this project. This includes:
*   **Google Cloud Project Context:** When running `gcloud` commands, always ensure the correct Google Cloud project is targeted. If not explicitly set as the default, use the `--project <PROJECT_ID>` flag.
*   Creating and modifying the directory structure.
*   Writing and updating Terraform and Ansible configuration files.
*   Generating and updating documentation, including this `GEMINI.md` file.
*   Following the user's instructions to build out the services.
*   I will not run `terraform` or `ansible` commands directly without user confirmation.