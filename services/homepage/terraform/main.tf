
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

variable "project_id" {
  description = "The GCP project ID."
  default     = "steffyd"
}

variable "region" {
  description = "The GCP region to deploy resources in."
  default     = "us-central1"
}

variable "domain_name" {
  description = "The custom domain for the homepage."
  default     = "steffyd.com"
}

variable "authorized_user_email" {
  description = "The Google account email to grant access to the homepage."
  default     = "danny.steffy@gmail.com"
}

variable "oauth2_client_id" {
  description = "The OAuth2 client ID for IAP configuration."
  type        = string
  sensitive   = true
}

variable "oauth2_client_secret" {
  description = "The OAuth2 client secret for IAP configuration."
  type        = string
  sensitive   = true
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
# Allow public access to the Cloud Run service
resource "google_cloud_run_service_iam_binding" "public_access" {
  location = google_cloud_run_v2_service.homepage_service.location
  service  = google_cloud_run_v2_service.homepage_service.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

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

# 5. Define the Cloud Run service.
resource "google_cloud_run_v2_service" "homepage_service" {
  name     = "homepage"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.homepage_sa.email

    containers {
      image = "gethomepage/homepage:latest"
      ports {
        container_port = 3000
      }

      env {
        name  = "HOMEPAGE_ALLOWED_HOSTS"
        value = "steffyd.com,homepage-795297610167.us-central1.run.app,homepage-y656lz7g6q-uc.a.run.app"
      }

      env {
        name  = "HOMEPAGE_CONFIG_BUCKET"
        value = google_storage_bucket.homepage_config_bucket.name
      }

      env {
        name  = "HOMEPAGE_IMAGES_BUCKET"
        value = google_storage_bucket.homepage_images_bucket.name
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

# 6. Domain mapping is handled by the load balancer, not directly to Cloud Run
# This ensures traffic goes through IAP for authentication

# 7. Create a Serverless NEG for the Cloud Run service.
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "homepage-serverless-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_v2_service.homepage_service.name
  }
}

# 8. Create a Backend Service.
resource "google_compute_backend_service" "backend_service" {
  name                            = "homepage-backend-service"
  protocol                        = "HTTP"
  port_name                       = "http"
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  enable_cdn                      = false
  iap {
    oauth2_client_id     = var.oauth2_client_id
    oauth2_client_secret = var.oauth2_client_secret
    enabled              = true
  }
  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
}

# 9. Create a URL map to route incoming requests to the backend service.
resource "google_compute_url_map" "url_map" {
  name            = "homepage-url-map"
  default_service = google_compute_backend_service.backend_service.id
}

# 10. Create a managed SSL certificate.
resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  name    = "homepage-ssl-cert"
  managed {
    domains = [var.domain_name]
  }
}

# 11. Create a target HTTPS proxy to route requests to the URL map.
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "homepage-https-proxy"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_certificate.id]
}

# 12. Create a global forwarding rule to handle and route incoming requests.
resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  name                  = "homepage-forwarding-rule"
  target                = google_compute_target_https_proxy.https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# 13. Create a managed DNS zone for the custom domain.
resource "google_dns_managed_zone" "steffyd_zone" {
  name     = "steffyd-zone"
  dns_name = "${var.domain_name}."
}

# 14. Add A record pointing to the load balancer IP (IAP will handle authentication)
resource "google_dns_record_set" "homepage_dns_a_records" {
  name         = google_dns_managed_zone.steffyd_zone.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.steffyd_zone.name
  rrdatas      = [google_compute_global_forwarding_rule.forwarding_rule.ip_address]
}

# 15. Grant the authorized user access to the IAP-secured backend service.
resource "google_iap_web_backend_service_iam_member" "iap_user" {
  project              = var.project_id
  web_backend_service  = google_compute_backend_service.backend_service.name
  role                 = "roles/iap.httpsResourceAccessor"
  member               = "user:${var.authorized_user_email}"
}

# 15b. Grant the IAP service account access to the IAP-protected backend service
resource "google_iap_web_backend_service_iam_member" "iap_service_account" {
  project              = var.project_id
  web_backend_service  = google_compute_backend_service.backend_service.name
  role                 = "roles/iap.httpsResourceAccessor"
  member               = "serviceAccount:${google_service_account.iap_sa.email}"
}

# 16. Enable IAP API (this creates the IAP service account)
resource "google_project_service" "iap_api" {
  service = "iap.googleapis.com"
  disable_on_destroy = false
}

# 17. Create IAP service account (this is needed for IAP to work)
resource "google_service_account" "iap_sa" {
  account_id   = "iap-service-account"
  display_name = "IAP Service Account"
  description  = "Service account for IAP to invoke Cloud Run services"
}

# 18. Grant the IAP service account permission to invoke the Cloud Run service
# Note: This might be redundant since we now allow allUsers, but keeping for completeness
resource "google_cloud_run_service_iam_member" "iap_invoker" {
  service  = google_cloud_run_v2_service.homepage_service.name
  location = google_cloud_run_v2_service.homepage_service.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.iap_sa.email}"
  
  depends_on = [google_project_service.iap_api]
}

# Data source to get project number for IAP service account
data "google_project" "project" {
  project_id = var.project_id
}

# Output the nameservers for the DNS zone.
output "dns_name_servers" {
  description = "The nameservers for the managed DNS zone. Update these in your domain registrar."
  value       = google_dns_managed_zone.steffyd_zone.name_servers
}

# Output the URL of the deployed service.
output "homepage_url" {
  description = "The URL of the homepage service."
  value       = "https://steffyd.com"
}

output "load_balancer_ip" {
  description = "The IP address of the load balancer."
  value = google_compute_global_forwarding_rule.forwarding_rule.ip_address
}
