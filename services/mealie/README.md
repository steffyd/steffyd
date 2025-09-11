# Mealie Service

This directory contains the configuration for the `mealie` service - a self-hosted recipe manager deployed on Google Cloud Run.

## Overview

Mealie is a self-hosted recipe manager that allows you to store, organize, and manage your recipes. This configuration deploys Mealie on Google Cloud Run with:

- **Database**: PostgreSQL on Cloud SQL
- **Storage**: Google Cloud Storage for data persistence
- **Compute**: Cloud Run for serverless container hosting
- **DNS**: Cloud DNS for domain management
- **Security**: Public access (can be secured with IAP if needed)

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Cloud DNS     │    │   Cloud Run     │    │   Cloud SQL     │
│   (Domain)      │───▶│   (Mealie)      │───▶│   (PostgreSQL)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Note:** Mealie manages its own data internally and doesn't require external file storage or configuration uploads.

## Prerequisites

Before deploying, ensure you have:

1. **Google Cloud SDK**: Install and authenticate with `gcloud auth application-default login`
2. **Terraform**: Version >= 1.0
3. **Ansible**: With Google Cloud collections installed
4. **Domain Access**: Ability to update DNS records for your domain

## Configuration

### 1. Terraform Variables

Copy the example variables file and configure your settings:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your values:

```hcl
# GCP Configuration
project_id = "steffyd"
region     = "us-central1"

# Mealie Configuration
mealie_domain = "mealie.steffyd.com"

# Database Configuration
db_password = "your-secure-database-password-here"

# Admin Configuration
admin_email    = "your-email@example.com"
admin_password = "your-secure-admin-password-here"
```

### 2. Required GCP APIs

Ensure the following APIs are enabled in your GCP project:

- Cloud Run API (`run.googleapis.com`)
- Cloud SQL Admin API (`sqladmin.googleapis.com`)
- Cloud DNS API (`dns.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## Deployment

### Step 1: Setup Terraform State

```bash
cd terraform/
./setup.sh
```

This creates the GCS bucket for storing Terraform state.

### Step 2: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

After deployment, note the `dns_name_servers` output. You'll need to update your domain registrar to use these nameservers.

### Step 3: Configure DNS

Update your domain's nameservers to point to the values from the Terraform output:

```
# Example nameservers (use the actual values from terraform output)
ns-cloud-a1.googledomains.com.
ns-cloud-a2.googledomains.com.
ns-cloud-a3.googledomains.com.
ns-cloud-a4.googledomains.com.
```

### Step 4: Access Mealie

Once the deployment is complete, Mealie will be available at your configured domain (e.g., `https://mealie.steffyd.com`). No additional configuration uploads are needed as Mealie manages its own data internally.

## Local Testing

You can test Mealie locally using Docker:

```bash
# Run Mealie locally with a local database
docker run -d \
  --name mealie \
  -p 9000:9000 \
  -e DB_ENGINE=sqlite \
  -e POSTGRES_DB=mealie.db \
  ghcr.io/mealie-recipes/mealie:v3.0.2

# Access Mealie at http://localhost:9000
```

## Accessing Mealie

Once deployed, Mealie will be available at your configured domain (e.g., `https://mealie.steffyd.com`).

### Default Login

- **Email**: The email you configured in `admin_email`
- **Password**: The password you configured in `admin_password`

## Configuration

Mealie is configured entirely through environment variables set in the Cloud Run service. No external configuration files are needed as Mealie manages its own data and settings internally.

## Customization

### Custom Themes

To add custom themes or modifications:

1. Create a custom Dockerfile based on the official Mealie image
2. Build and push your custom image to Google Artifact Registry
3. Update the `image` field in `terraform/main.tf`

### Environment Variables

Additional environment variables can be added to the Cloud Run service in `terraform/main.tf`:

```hcl
env {
  name  = "CUSTOM_VAR"
  value = "custom_value"
}
```

## Monitoring and Logs

### Cloud Run Logs

View Mealie logs in the Google Cloud Console:

1. Go to Cloud Run in the GCP Console
2. Click on the `mealie` service
3. Go to the "Logs" tab

### Database Monitoring

Monitor the Cloud SQL instance:

1. Go to SQL in the GCP Console
2. Click on the `mealie-postgres-instance`
3. View metrics and logs

## Backup and Recovery

### Database Backups

Cloud SQL automatically creates daily backups. To restore:

1. Go to SQL in the GCP Console
2. Click on your instance
3. Go to "Backups" tab
4. Click "Restore" on the desired backup

### Data Files

Mealie data files are stored in the Cloud Storage bucket. To backup:

```bash
# Download all data
gsutil -m cp -r gs://steffyd-mealie-data ./backup/

# Upload to restore
gsutil -m cp -r ./backup/ gs://steffyd-mealie-data/
```

## Troubleshooting

### Common Issues

1. **Service won't start**: Check Cloud Run logs for errors
2. **Database connection issues**: Verify Cloud SQL instance is running and accessible
3. **DNS not resolving**: Ensure nameservers are correctly configured
4. **Permission errors**: Check IAM roles and service account permissions

### Useful Commands

```bash
# Check Cloud Run service status
gcloud run services describe mealie --region=us-central1

# View recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=mealie" --limit=50

# Check database status
gcloud sql instances describe mealie-postgres-instance
```

## Security Considerations

- The current configuration allows public access to Mealie
- Consider implementing Identity-Aware Proxy (IAP) for additional security
- Regularly update the Mealie Docker image
- Use strong passwords for database and admin accounts
- Enable Cloud SQL SSL connections in production

## Cost Optimization

- Cloud Run scales to zero when not in use
- Cloud SQL uses the smallest instance tier (`db-f1-micro`)
- Consider using Cloud SQL with automatic storage increases
- Monitor usage and adjust resource limits as needed

## Support

For issues with:

- **Mealie application**: Check the [official documentation](https://docs.mealie.io/)
- **Infrastructure**: Review Terraform and Cloud Run logs
- **Configuration**: Check Ansible playbook execution logs
