# Homepage Service

This directory contains the configuration for the `homepage` service.

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
    - Identity-Aware Proxy (IAP) API (`iap.googleapis.com`)
    - Cloud DNS API (`dns.googleapis.com`)
    - Cloud Storage API (`storage.googleapis.com`)
    - Identity and Access Management (IAM) API (`iam.googleapis.com`)
    - Cloud Build API (`cloudbuild.googleapis.com`)

3.  **Configured IAP OAuth Consent Screen:** The service is secured with Identity-Aware Proxy (IAP). You **must** configure the OAuth consent screen in the GCP console before deploying. This is a one-time setup for your project.
    1.  Navigate to the [OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent) in the GCP Console.
    2.  For "User Type", select **External** and click **Create**.
    3.  On the next page, fill in the required fields:
        - **App name:** `Steffyd Homepage` (or a name of your choice).
        - **User support email:** Select your email address.
        - **Developer contact information:** Enter your email address.
    4.  Click **Save and Continue**.
    5.  On the "Scopes" page, click **Save and Continue** (no scopes are needed for IAP).
    6.  On the "Test users" page, click **Save and Continue**.
    7.  You will be returned to the summary page. Your consent screen is now configured.

4.  **OAuth2 Credentials:** You need to create OAuth2 credentials for IAP:
    1.  Navigate to [APIs & Services > Credentials](https://console.cloud.google.com/apis/credentials) in the GCP Console.
    2.  Click **Create Credentials** > **OAuth 2.0 Client IDs**.
    3.  Select **Web application** as the application type.
    4.  Give it a name (e.g., "Homepage IAP Client").
    5.  Add authorized redirect URIs (you can use `https://steffyd.com` for now).
    6.  Click **Create** and note down the Client ID and Client Secret.

5.  **Variables:** Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your OAuth2 credentials:
    ```bash
    cp terraform.tfvars.example terraform.tfvars
    # Edit terraform.tfvars with your OAuth2 credentials
    ```

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
    *   After `terraform apply` completes, note the `dns_name_servers` output. You will need to update your domain registrar (e.g., Squarespace) to use these nameservers for `steffyd.com`.

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