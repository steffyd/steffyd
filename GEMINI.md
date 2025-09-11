# Gemini Project Analysis: steffyd

## Project Overview

This project, "steffyd," is intended to manage the infrastructure and configuration for a personal digital presence within the Google Cloud project `steffyd`. It will be hosted as a GitHub repository. The project is designed to be managed using a combination of Terraform for infrastructure provisioning and Ansible for configuration management, with a clear, service-oriented directory structure.

## Core Components

*   **Homepage:** A personal homepage/dashboard, similar to the one in the `Navicomputer-Core` project.
*   **Mealie:** A self-hosted recipe manager instance.

## Architecture and Technology

*   **Directory Structure:** The project is organized into a `services/` directory, with subdirectories for each service (`homepage`, `mealie`). Each service directory contains its own `terraform/` and `ansible/` subdirectories.
*   **Homepage Service:**
    *   **Infrastructure:** Deployed as a serverless container on Google Cloud Run. The entire infrastructure, including the Cloud DNS zone and records, is defined in Terraform.
    *   **Configuration:** Application configuration files (YAML, CSS) are uploaded to a dedicated Google Cloud Storage bucket via an Ansible playbook.
    *   **GCS Upload Workaround:** Due to compatibility issues between the `google.cloud.gcp_storage_object` Ansible module and Python 3.13 (specifically a `TypeError: a bytes-like object is required, not 'str'` originating from the `google-crc32c` library), the Ansible playbook for GCS uploads (`services/homepage/ansible/upload_config.yml`) has been modified to use `gsutil` commands directly via the `ansible.builtin.command` module. This bypasses the problematic Python module.
    *   **Authentication:** Access is secured using Google's Identity-Aware Proxy (IAP), with authorized users defined in the Terraform configuration.
    *   **Domain:** Mapped to a custom domain (`steffyd.com`) using a Cloud Run Domain Mapping and a managed Cloud DNS zone.
*   **Infrastructure as Code:** Terraform is the primary tool for provisioning all cloud resources (Cloud Run, GCS, IAM, Cloud DNS).
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
