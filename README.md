# Employee Lifecycle Platform on Kubernetes (AWS)

Automated employee onboarding and offboarding platform on AWS using Kubernetes (EKS), Terraform, Cognito, AWS Managed Microsoft AD and WorkSpaces.

This repository is structured as a portfolio project: infrastructure as code, Kubernetes manifests, application code and evidence screenshots.

## Architecture

![Architecture overview](docs/screenshots/architecture/01-architecture-overview.png)

## What it does

**Onboarding**
- Admin creates a new employee via a self-service portal
- Platform provisions:
  - Database record
  - Cognito user and group assignment
  - Active Directory user in the correct OU
  - WorkSpace provisioning
  - Role-based tooling and configuration via AD policies

**Offboarding**
- Admin terminates an employee
- Platform disables access and cleans up:
  - Removes employee from the application database
  - Disables Cognito user
  - Disables AD user
  - Terminates WorkSpace

## Tech stack

- Terraform for AWS infrastructure
- AWS EKS for Kubernetes
- AWS Cognito for authentication and group-based access
- AWS Managed Microsoft AD for directory services
- Amazon WorkSpaces for VDI provisioning
- Kubernetes NetworkPolicy for micro-segmentation

## Evidence: Onboarding flow (screenshots)

1) Admin creates employee (admin only UI)

![Create employee form](docs/screenshots/onboarding/01-admin-create-employee-form.png)

2) Employee appears in directory list

![Created employee record](docs/screenshots/onboarding/02-created-employee-new-database-record.png)

3) Backend confirms provisioning steps

![Onboarding backend response](docs/screenshots/onboarding/02-succesfull-onboarding-response-from-backend.png)

4) Cognito user created and enabled

![Cognito user created](docs/screenshots/onboarding/03-cognito-user-created.png)

5) AD user created in the correct OU

![AD user created in OU](docs/screenshots/onboarding/04-ad-user-created-ou.png)

6) WorkSpace provisioning started

![WorkSpace provisioning started](docs/screenshots/onboarding/05-workspace-provisioning-start.png)

7) Tooling proof inside the WorkSpace

![WorkSpace tooling proof](docs/screenshots/onboarding/06-workspace-tooling-proof.png)

## Evidence: Offboarding flow (screenshots)

You asked to keep all offboarding screenshots, so this section includes the full chain.

1) Employee visible in the portal

![Portal directory and Term action](docs/screenshots/offboarding/01-portal-offboarding-confirmation.png)

2) Offboarding success confirmation

![Offboarding confirmation popup](docs/screenshots/offboarding/02-portal-offboarding-confirmation.png)

3) Employee removed from database

![Removed from database](docs/screenshots/offboarding/02-removed-from-database.png)

4) Cognito user disabled

![Cognito disabled](docs/screenshots/offboarding/03-cognito-disabled.png)

5) AD user disabled

![AD user disabled](docs/screenshots/offboarding/04-ad-user-disabled.png)

6) WorkSpace terminating state

![WorkSpace terminating](docs/screenshots/offboarding/05-workspace-terminating.png)

7) WorkSpace terminated state

![WorkSpace terminated](docs/screenshots/offboarding/05-workspace-terminated.png)

## Security model

### Cognito groups and access model

![Cognito groups](docs/screenshots/rbac/01-cognito-groups.png)

Access is controlled via Cognito groups that map to application roles.

### Kubernetes micro-segmentation

Network access is restricted using Kubernetes NetworkPolicy.

![NetworkPolicy describe output](docs/screenshots/kubernetes/02-networkpolicy-employee-portal.png)

## Reliability evidence

Kubernetes self-healing is demonstrated by deleting a pod and letting the Deployment recreate it.

![Self-healing demo](docs/screenshots/kubernetes/01-self-healing-pod-delete.png)

## Repository structure

- `terraform/` Terraform root module (all `.tf` files are loaded from this directory)
- `kubernetes/` Kubernetes manifests for the platform
- `employee-portal/` Application source code
- `automation/scripts/` Supporting scripts
- `architecture/diagrams/` Architecture diagrams
- `docs/screenshots/` Evidence screenshots used in this README

Terraform loads configuration files from the root module directory, so this repo uses a single root module under `terraform/`. :contentReference[oaicite:5]{index=5}

## Quick start (local)

### Prerequisites
- Terraform 1.6+
- AWS CLI configured
- kubectl

### 1) Clone
```bash
git clone https://github.com/Sonny-He/employee-lifecycle-platform-kubernetes.git
cd employee-lifecycle-platform-kubernetes
