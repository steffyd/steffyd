# Terraform configuration for the homepage service, deployed on Google Cloud Run.

terraform {
  backend "gcs" {
    bucket = "steffyd-terraform-state"
    prefix = "homepage/terraform.tfstate"
  }
}

provider "google" {
  project = "steffyd"
  region  = "us-central1"
}

provider "google-beta" {
  project = "steffyd"
  region  = "us-central1"
}

variable "project_id" {
  description = "The GCP project ID."
  default     = "steffyd"
}

variable "region" {
  description = "The GCP region to deploy resources in."
  default     = "us-central1"
}

variable "google_oauth_client_id" {
  description = "Google OAuth Client ID."
  type        = string
  sensitive   = true
}

variable "google_oauth_client_secret" {
  description = "Google OAuth Client Secret."
  type        = string
  sensitive   = true
}

variable "cookie_secret" {
  description = "Secret for cookie session. Must be 32 characters long."
  type        = string
  sensitive   = true
}

variable "authorized_user_email" {
  description = "The Google account email to grant access to the homepage."
  type        = string
}

variable "mealie_api_key" {
  description = "API key for Mealie widget integration."
  type        = string
  sensitive   = true
}

variable "port" {
  description = "The port for the OAuth2-proxy container."
  type        = number
  default     = 8080
}

# 1. Create a GCS bucket to store the homepage configuration files (YAMLs).
resource "google_storage_bucket" "homepage_config_bucket" {
  name          = "${var.project_id}-homepage-config"
  location      = "US"
  force_destroy = false
}

# 2. Create a separate GCS bucket to store the homepage image files.
resource "google_storage_bucket" "homepage_images_bucket" {
  name          = "${var.project_id}-homepage-images"
  location      = "US"
  force_destroy = false
}

# 3. Create a dedicated service account for the Cloud Run service.
resource "google_service_account" "homepage_sa" {
  account_id   = "homepage-run-sa"
  display_name = "Homepage Cloud Run Service Account"
}


# 4. Grant the service account proper IAM permissions.

# Grant storage object admin role for config bucket
resource "google_storage_bucket_iam_member" "homepage_config_admin" {
  bucket = google_storage_bucket.homepage_config_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.homepage_sa.email}"
}

# Grant storage object viewer role for images bucket
resource "google_storage_bucket_iam_member" "homepage_images_reader" {
  bucket = google_storage_bucket.homepage_images_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.homepage_sa.email}"
}

# 5. Define the Cloud Run service with OAuth2-proxy sidecar.
resource "google_cloud_run_v2_service" "homepage_service" {
  provider = google-beta
  name     = "homepage"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.homepage_sa.email
    
    # Container dependencies - homepage waits for oauth2-proxy
    annotations = {
      "run.googleapis.com/container-dependencies" = jsonencode({
        "homepage" = ["oauth2-proxy"]
      })
    }

    # OAuth2-proxy sidecar container
    containers {
      name  = "oauth2-proxy"
      image = "mirror.gcr.io/bitnami/oauth2-proxy@sha256:bcf515026e66f1c869513487bee973fdf174eea305bfe4fc2db51c523a70d213"
      
      env {
        name = "OAUTH2_PROXY_HTTP_ADDRESS"
        value = "0.0.0.0:8080"
      }
      env {
        name = "OAUTH2_PROXY_PROVIDER"
        value = "google"
      }
      env {
        name = "OAUTH2_PROXY_EMAIL_DOMAINS"
        value = "gmail.com"
      }
      env {
        name = "OAUTH2_PROXY_WHITELIST_EMAILS"
        value = var.authorized_user_email
      }
      env {
        name = "OAUTH2_PROXY_CLIENT_ID"
        value = var.google_oauth_client_id
      }
      env {
        name = "OAUTH2_PROXY_CLIENT_SECRET"
        value = var.google_oauth_client_secret
      }
      env {
        name = "OAUTH2_PROXY_COOKIE_SECRET"
        value = var.cookie_secret
      }
      env {
        name = "OAUTH2_PROXY_REDIRECT_URL"
        value = "https://steffyd.com/oauth2/callback"
      }
      env {
        name = "OAUTH2_PROXY_COOKIE_SECURE"
        value = "true"
      }
      env {
        name = "OAUTH2_PROXY_SKIP_PROVIDER_BUTTON"
        value = "true"
      }
      env {
        name = "OAUTH2_PROXY_SSL_UPSTREAM_INSECURE_SKIP_VERIFY"
        value = "true"
      }
      
      args = [
        "--upstream=http://127.0.0.1:3000/",
        "--pass-host-header=false",
        "--pass-user-headers=true",
        "--set-xauthrequest=true"
      ]
      
      ports {
        container_port = var.port
        name           = "http1"
      }
      
      resources {
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
        cpu_idle = true
      }
      
      
      startup_probe {
        tcp_socket {
          port = var.port
        }
        timeout_seconds   = 240
        period_seconds    = 240
        failure_threshold = 1
      }
    }

    # Homepage container (no external port)
    containers {
      name  = "homepage"
      image = "gethomepage/homepage:latest"
      
      # No ports block - not externally accessible

      env {
        name  = "HOMEPAGE_CONFIG_BUCKET"
        value = google_storage_bucket.homepage_config_bucket.name
      }

      env {
        name  = "HOMEPAGE_IMAGES_BUCKET"
        value = google_storage_bucket.homepage_images_bucket.name
      }

      env {
        name  = "HOMEPAGE_ALLOWED_HOSTS"
        value = "steffyd.com,homepage-795297610167.us-central1.run.app"
      }

      env {
        name  = "MEALIE_API_KEY"
        value = var.mealie_api_key
      }


      # Mount the config GCS bucket to /app/config.
      volume_mounts {
        name       = "config-volume"
        mount_path = "/app/config"
      }

      # Mount the images GCS bucket to /app/public/images.
      volume_mounts {
        name       = "images-volume"
        mount_path = "/app/public/images"
      }
    }

    # Define the volume that connects to our config GCS bucket.
    volumes {
      name = "config-volume"
      gcs {
        bucket = google_storage_bucket.homepage_config_bucket.name
        read_only = false # The app might need to write cache or log files.
      }
    }

    # Define the volume that connects to our images GCS bucket.
    volumes {
      name = "images-volume"
      gcs {
        bucket = google_storage_bucket.homepage_images_bucket.name
        read_only = false
      }
    }
    
  }
}

# Data source to get project information
data "google_project" "project" {
  project_id = var.project_id
}

# Allow unauthenticated access to the homepage service
# Security is handled by the OAuth2 proxy - only authenticated users reach this service
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.homepage_service.location
  name     = google_cloud_run_v2_service.homepage_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Domain mapping for steffyd.com
resource "google_cloud_run_domain_mapping" "homepage_domain" {
  location = google_cloud_run_v2_service.homepage_service.location
  name     = "steffyd.com"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.homepage_service.name
  }
}

# Output the URL of the deployed service.
output "homepage_url" {
  description = "The URL of the homepage service."
  value       = google_cloud_run_v2_service.homepage_service.uri
}

output "homepage_domain_url" {
  description = "The custom domain URL of the homepage service."
  value       = "https://steffyd.com"
}