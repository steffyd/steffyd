# steffyd

This repository contains the infrastructure and configuration for my personal digital presence, including my homepage and Mealie instance.

## Architecture

The architecture uses a **sidecar pattern** for authentication. A regional load balancer routes traffic to a single Cloud Run service that contains both an OAuth2-proxy sidecar container and the homepage container. The OAuth2-proxy handles authentication and forwards traffic internally to the homepage container.

### Routing Flow
```
Internet → Regional Load Balancer → Homepage Service → OAuth2-proxy Sidecar → Homepage Container
```

- **External Access**: Only through `steffyd.com` via the load balancer
- **Authentication**: OAuth2-proxy sidecar handles Google OAuth authentication
- **Internal Communication**: OAuth2-proxy forwards to homepage container via `127.0.0.1:3000`
- **Security**: Homepage container is not directly accessible from the internet

## Structure

This project is organized by service, with each service having its own Terraform and Ansible configurations.

-   `components/`: Contains shared infrastructure components.
    -   `regional-load-balancer/`: The Terraform configuration for the regional load balancer.
-   `services/`: Contains the configuration for each individual service.
    -   `homepage/`: Contains all configuration for the personal homepage with OAuth2-proxy sidecar. See the [service README](./services/homepage/README.md) for local testing instructions.
    -   `mealie/`: The configuration for the Mealie recipe manager instance. See the [service README](./services/mealie/README.md) for deployment instructions.

## Deployment Order of Operations

Due to the dependencies between the different components, it is important to deploy them in the correct order.

1.  **Homepage Service (with OAuth2-proxy sidecar):**
    -   Deploy the `homepage` service by running `terraform apply` in the `services/homepage/terraform` directory.
    -   After the infrastructure is created, run the Ansible playbook in `services/homepage/ansible` to upload the configuration files.

2.  **Mealie Service:**
    -   Deploy the `mealie` service by running `terraform apply` in the `services/mealie/terraform` directory.

3.  **Regional Load Balancer:**
    -   Deploy the regional load balancer by running `terraform apply` in the `components/regional-load-balancer/terraform` directory.
    -   After the infrastructure is created, note the `dns_name_servers` output. You will need to update your domain registrar (e.g., Squarespace) to use these nameservers for your domain.

## Technology Stack

-   **Infrastructure as Code:** Terraform is used to provision all cloud resources, including Cloud Run services, GCS buckets, and the regional load balancer.
-   **Configuration Management:** Ansible is used to upload application configuration to GCS buckets.
-   **Cloud Provider:** Google Cloud Platform (GCP)