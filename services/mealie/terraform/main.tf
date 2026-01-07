# Terraform configuration for the Mealie service.
# This will be deployed on Google Cloud.

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "steffyd-terraform-state"
    prefix = "mealie"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "steffyd"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "mealie_domain" {
  description = "The domain for Mealie service"
  type        = string
  default     = "mealie.steffyd.com"
}

variable "db_password" {
  description = "Password for the Mealie database user"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Email for the Mealie admin user"
  type        = string
}

variable "admin_password" {
  description = "Password for the Mealie admin user"
  type        = string
  sensitive   = true
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Artifact Registry remote repository for GitHub Container Registry
resource "google_artifact_registry_repository" "ghcr" {
  location      = var.region
  repository_id = "ghcr"
  description   = "Remote repository for GitHub Container Registry"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"

  remote_repository_config {
    description = "GitHub Container Registry"
    docker_repository {
      custom_repository {
        uri = "https://ghcr.io"
      }
    }
  }

  depends_on = [google_project_service.apis]
}


# GCS bucket for Mealie persistent data storage
resource "google_storage_bucket" "mealie_data" {
  name          = "${var.project_id}-mealie-data"
  location      = "US"
  force_destroy = false

  uniform_bucket_level_access = true
}

# Cloud SQL instance for Mealie database
resource "google_sql_database_instance" "mealie_db" {
  name             = "mealie-postgres-instance"
  database_version = "POSTGRES_15"
  region           = var.region
  deletion_protection = false

  depends_on = [google_project_service.apis]

  settings {
    tier = "db-f1-micro"
    
    backup_configuration {
      enabled = true
      start_time = "03:00"
    }
    
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "all"
        value = "0.0.0.0/0"
      }
    }
  }
}

# Database for Mealie
resource "google_sql_database" "mealie_database" {
  name     = "mealie"
  instance = google_sql_database_instance.mealie_db.name
}

# Database user for Mealie
resource "google_sql_user" "mealie_user" {
  name     = "mealie"
  instance = google_sql_database_instance.mealie_db.name
  password = var.db_password
}


# Service account for Mealie
resource "google_service_account" "mealie_sa" {
  account_id   = "mealie-run-sa"
  display_name = "Mealie Cloud Run Service Account"
}

# Grant storage access to Mealie service account
resource "google_storage_bucket_iam_member" "mealie_storage_admin" {
  bucket = google_storage_bucket.mealie_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mealie_sa.email}"
}


# Cloud Run service for Mealie
resource "google_cloud_run_v2_service" "mealie" {
  name     = "mealie"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"  # Changed to allow public access
  
  depends_on = [google_project_service.apis]

  template {
    service_account = google_service_account.mealie_sa.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ghcr.repository_id}/mealie-recipes/mealie:latest"
      
      ports {
        container_port = 9000
        name           = "http1"
      }
      
      env {
        name  = "DB_ENGINE"
        value = "postgres"
      }
      
      env {
        name  = "POSTGRES_USER"
        value = google_sql_user.mealie_user.name
      }
      
      env {
        name  = "POSTGRES_PASSWORD"
        value = google_sql_user.mealie_user.password
      }
      
      env {
        name  = "POSTGRES_SERVER"
        value = google_sql_database_instance.mealie_db.public_ip_address  # Changed to public IP
      }
      
      env {
        name  = "POSTGRES_PORT"
        value = "5432"
      }
      
      env {
        name  = "POSTGRES_DB"
        value = google_sql_database.mealie_database.name
      }
      
      env {
        name  = "DATABASE_URL"
        value = "postgresql://${google_sql_user.mealie_user.name}:${google_sql_user.mealie_user.password}@${google_sql_database_instance.mealie_db.public_ip_address}:5432/${google_sql_database.mealie_database.name}"
      }
      
      
      env {
        name  = "DEFAULT_GROUP"
        value = "Home"
      }
      
      env {
        name  = "DEFAULT_EMAIL"
        value = var.admin_email
      }
      
      env {
        name  = "DEFAULT_PASSWORD"
        value = var.admin_password
      }
      
      env {
        name  = "BASE_URL"
        value = "https://${var.mealie_domain}"
      }
      
      # Mount GCS bucket as a volume for persistent storage
      volume_mounts {
        name       = "mealie-data-volume"
        mount_path = "/app/data"
      }
      
      resources {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
        cpu_idle = true
      }
    }
    
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Define the volume that connects to our Mealie data GCS bucket
    volumes {
      name = "mealie-data-volume"
      gcs {
        bucket = google_storage_bucket.mealie_data.name
        read_only = false
      }
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}

# Allow public access to Mealie service
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.mealie.location
  name     = google_cloud_run_v2_service.mealie.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Domain mapping for mealie.steffyd.com
resource "google_cloud_run_domain_mapping" "mealie_domain" {
  location = google_cloud_run_v2_service.mealie.location
  name     = "mealie.steffyd.com"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.mealie.name
  }
}

# DNS Configuration
# Use existing DNS zone
data "google_dns_managed_zone" "steffyd_zone" {
  name = "steffyd-lb-zone"
}

# Get the Cloud Run service URLs
data "google_cloud_run_v2_service" "homepage" {
  name     = "homepage"
  location = var.region
}

# CNAME record for steffyd.com pointing to homepage service
resource "google_dns_record_set" "homepage_cname" {
  name         = data.google_dns_managed_zone.steffyd_zone.dns_name
  type         = "CNAME"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.steffyd_zone.name
  rrdatas      = [replace(data.google_cloud_run_v2_service.homepage.uri, "https://", "")]
}

# CNAME record for mealie.steffyd.com pointing to mealie service
resource "google_dns_record_set" "mealie_cname" {
  name         = "mealie.steffyd.com."
  type         = "CNAME"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.steffyd_zone.name
  rrdatas      = [replace(google_cloud_run_v2_service.mealie.uri, "https://", "")]
}

# Outputs
output "mealie_url" {
  value = google_cloud_run_v2_service.mealie.uri
}

output "mealie_domain_url" {
  description = "The custom domain URL of the Mealie service."
  value       = "https://mealie.steffyd.com"
}

output "database_connection_name" {
  value = google_sql_database_instance.mealie_db.connection_name
}

output "storage_bucket" {
  value = google_storage_bucket.mealie_data.name
}

output "mealie_image_url" {
  description = "The full image URL for the Mealie service"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ghcr.repository_id}/mealie-recipes/mealie:latest"
}

output "dns_name_servers" {
  description = "The nameservers for the managed DNS zone. Update these in your domain registrar."
  value       = data.google_dns_managed_zone.steffyd_zone.name_servers
}

output "homepage_service_url" {
  description = "The Cloud Run service URL for homepage"
  value       = data.google_cloud_run_v2_service.homepage.uri
}

