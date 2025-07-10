# Gemini Project Analysis

This document provides a summary of the `mastodon-oracle-cloud-free-tier` project.

## Project Overview

This project automates the deployment of a Mastodon instance on Oracle Cloud's Always Free tier using Terraform and Ansible.

## Core Technologies

- **Infrastructure as Code:** Terraform is used to provision the necessary Oracle Cloud Infrastructure (OCI) resources, including a compute instance, block storage, and networking.
- **Configuration Management:** Ansible is used to configure the server, install Docker, and deploy the Mastodon application using Docker Compose.
- **Containerization:** Mastodon and its dependencies (PostgreSQL, Redis, Elasticsearch) are run in Docker containers.

## Project Structure

- `terraform/`: Contains the Terraform configuration (`main.tf`) for creating the OCI resources.
- `ansible.cfg`: Ansible configuration file.
- `inventory.ini.sample`: A sample Ansible inventory file. The real one is inventory.ini, but git-ignored.
- `mastodon.yaml`: The main Ansible playbook for setting up the Mastodon instance.
- `group_vars/mastodon/vars.yaml`: Ansible variables for configuring the Mastodon instance, including domain names, versions, and secrets.
- `roles/`: Contains Ansible roles for different parts of the setup:
    - `common-noroot`: Basic setup for the `ubuntu` user.
    - `common-root`: System-level configuration, including package installation and security hardening with `sshguard`.
    - `docker`: Installs Docker and Docker Compose.
    - `mastodon`: The main role for configuring and deploying Mastodon. It includes templates for Docker Compose, Caddy, and various scripts.
    - `newrelic`: (Optional) Installs the New Relic agent for monitoring.
- `requirements.txt`: Python dependencies for Ansible.
- `ansible-galaxy-reqs.yaml` and `ansible-galaxy-collection-reqs.yaml`: Ansible Galaxy dependencies.
- `Makefile`: Contains convenience targets for initializing the project and updating dependencies.
- `README.md`: Detailed instructions for setting up and using the project.

## Key Files

- `terraform/main.tf`: Defines the Oracle Cloud infrastructure.
- `mastodon.yaml`: The main Ansible playbook that orchestrates the entire configuration process.
- `group_vars/mastodon/vars.yaml`: The primary file for user-specific configuration. This is where the user will define their domain, Mastodon version, and other settings.
- `roles/mastodon/templates/docker-compose.yaml`: The template for the Docker Compose file that defines the Mastodon services.
- `roles/mastodon/templates/Caddyfile`: The template for the Caddy web server configuration.
- `roles/mastodon/tasks/main.yaml`: The main task file for the `mastodon` role, which contains the logic for setting up the Mastodon application.

## Optional Features

The project includes optional features that can be enabled by the user:

- **Backups with Kopia:** The `mastodon` role includes tasks for setting up backups using Kopia. This is configured through variables in `group_vars/mastodon/vars.yaml` and the `roles/mastodon/templates/kopia.sh` and `roles/mastodon/templates/backup.sh` scripts.
- **New Relic Monitoring:** The `newrelic` role can be used to install the New Relic agent for monitoring the server. This is configured through variables in `group_vars/mastodon/vars.yaml`.
- **Pushover and Healthchecks.io:** The project supports sending notifications for cron job failures using Pushover and Healthchecks.io. These are configured through variables in `group_vars/mastodon/vars.yaml`.

## Deployment Workflow

1.  **Prerequisites:** The user needs to have an Oracle Cloud account, Terraform, and Ansible installed.
2.  **Terraform:**
    - Create a `terraform.tfvars` file in the `terraform/` directory with the required OCI credentials.
    - Run `terraform init` and `terraform apply` to provision the infrastructure.
3.  **Ansible:**
    - Update `inventory.ini` with the IP address of the newly created server.
    - Configure `group_vars/mastodon/vars.yaml` with the desired settings.
    - Run `ansible-playbook mastodon.yaml --tags bootstrap` to prepare the block storage.
    - Run `ansible-playbook mastodon.yaml` to deploy and configure Mastodon.
4.  **Mastodon Setup:**
    - Run the one-time Mastodon setup command to create an admin user and generate secrets.
    - Update the Ansible Vault with the generated secrets and re-run the playbook.

## Secrets Management

The project uses Ansible Vault to manage secrets. The `group_vars/mastodon/vars.yaml` file references variables that are expected to be in a `vault.yaml` file in the same directory. The `README.md` provides instructions on how to set up and use Ansible Vault.

## Development Guidelines

- Every Ansible playbook change should be tested with the `-C` (check) option before deployment.