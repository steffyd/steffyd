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
    "dns.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
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

# Note: Mealie manages its own data internally and doesn't require a GCS bucket

# Cloud Run service for Mealie
resource "google_cloud_run_v2_service" "mealie" {
  name     = "mealie"
  location = var.region
  
  depends_on = [google_project_service.apis]

  template {
    containers {
      image = "ghcr.io/mealie-recipes/mealie:v3.0.2"
      
      ports {
        container_port = 9000
      }
      
      env {
        name  = "DB_ENGINE"
        value = "postgresql"
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
        value = google_sql_database_instance.mealie_db.private_ip_address
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
        name  = "REDIS_URL"
        value = "redis://redis:6379"
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
      
      resources {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
    }
    
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}

# IAM policy for Cloud Run
resource "google_cloud_run_service_iam_policy" "mealie_noauth" {
  location = google_cloud_run_v2_service.mealie.location
  project  = google_cloud_run_v2_service.mealie.project
  service  = google_cloud_run_v2_service.mealie.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Cloud DNS zone for the domain
resource "google_dns_managed_zone" "mealie_zone" {
  name        = "mealie-zone"
  dns_name    = "mealie.steffyd.com."
  description = "DNS zone for Mealie service"
}

# DNS record for Mealie
resource "google_dns_record_set" "mealie_dns" {
  name = google_dns_managed_zone.mealie_zone.dns_name
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.mealie_zone.name

  rrdatas = [google_cloud_run_v2_service.mealie.uri]
}

# Outputs
output "mealie_url" {
  value = google_cloud_run_v2_service.mealie.uri
}

output "dns_name_servers" {
  value = google_dns_managed_zone.mealie_zone.name_servers
}

output "database_connection_name" {
  value = google_sql_database_instance.mealie_db.connection_name
}
