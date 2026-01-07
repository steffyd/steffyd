Access is controlled by the OAuth2-proxy sidecar.
- **External Access**: Only through `steffyd.com`
# Homepage Service

This directory contains the configuration for the `homepage` service.

This service is deployed as a Cloud Run service with an OAuth2-proxy sidecar container. The OAuth2-proxy handles authentication and forwards traffic internally to the homepage container. Access is controlled by the OAuth2-proxy sidecar.

## Architecture

The homepage service uses a **sidecar pattern** where two containers run in the same Cloud Run service:

- **OAuth2-proxy sidecar** (port 4180): Handles Google OAuth authentication
- **Homepage container** (port 3000): Serves the actual homepage content

### Security Model

- **External Access**: Only through `steffyd.com`
- **Authentication**: OAuth2-proxy sidecar handles Google OAuth authentication
- **Internal Communication**: OAuth2-proxy forwards to homepage container via `127.0.0.1:3000`
- **Direct Access**: Homepage container is not directly accessible from the internet

## Local Testing

You can test changes to the homepage configuration locally before deploying them. This allows you to see how your dashboard will look and behave.

1.  Make sure you have Docker installed and running.
2.  Navigate to the root directory of this project (`/Users/thestiffy/Code/steffyd`).
    ```bash
    cd /Users/thestiffy/Code/steffyd
    ```
3.  Run the following command from the project root:

    ```bash
    docker run --name homepage -p 3000:3000 -v $(pwd)/services/homepage/config:/app/config -v $(pwd)/services/homepage/config/images:/app/public/images gethomepage/homepage:latest
    ```
4.  Open your web browser and navigate to `http://localhost:3000`.

This command starts the homepage container and mounts your local `config` directory. It is critical to run the command from the project's root directory so the volume path `$(pwd)/services/homepage/config` resolves correctly. Any changes you make to the files in `services/homepage/config` will be reflected instantly when you refresh your browser.

## Deployment

This service is deployed using a combination of Terraform and Ansible.

### Terraform Prerequisites

The Terraform configuration will provision all necessary GCP resources. Before running, ensure you have:

1.  **Authenticated to GCP:** You must authenticate your local environment. The simplest way is to use the gcloud CLI:
    ```bash
    gcloud auth application-default login
    ```

2.  **Enabled GCP APIs:** Ensure the following APIs are enabled in your `steffyd` GCP project. Terraform will prompt you if any are missing, but it's best to enable them first:
    - Cloud Run API (`run.googleapis.com`)
    - Cloud Storage API (`storage.googleapis.com`)
    - Identity and Access Management (IAM) API (`iam.googleapis.com`)
    - Cloud Build API (`cloudbuild.googleapis.com`)

### Ansible Prerequisites

The Ansible playbook uploads the contents of the `config/` directory to the GCS bucket created by Terraform.

1.  **Authenticated to GCP:** Just like with Terraform, Ansible requires an authenticated environment. The `gcloud auth application-default login` command will also work for Ansible.

2.  **Install Ansible Collections:** The playbook depends on the `community.google` collection. Install it using the provided `requirements.yml` file:
    ```bash
    ansible-galaxy install -r ansible/requirements.yml
    ```

3.  **Bucket Name:** The playbook assumes the GCS bucket is named `steffyd-homepage-config`, which matches the name defined in the Terraform configuration. If you change the bucket name in Terraform, you must update it in `ansible/upload_config.yml` as well.

### Deployment Steps

Follow these steps to deploy the Homepage service:

1.  **Setup Terraform State Bucket:**
    *   Navigate to the Terraform directory:
        ```bash
        cd terraform/
        ```
    *   Run the setup script to create the GCS bucket for Terraform state:
        ```bash
        ./setup.sh
        ```

2.  **Deploy Infrastructure (Terraform):**
    *   Initialize Terraform (this will configure the remote state backend):
        ```bash
        terraform init
        ```
    *   Review the plan (optional but recommended):
        ```bash
        terraform plan
        ```
    *   Apply the changes:
        ```bash
        terraform apply
        ```

3.  **Upload Configuration (Ansible):**
    *   Navigate to the Ansible directory:
        ```bash
        cd ../ansible/
        ```
    *   Install Ansible collections (if you haven't already):
        ```bash
        ansible-galaxy install -r requirements.yml
        ```
    *   Run the playbook to upload configuration files:
        ```bash
        ansible-playbook upload_config.yml
        ```
