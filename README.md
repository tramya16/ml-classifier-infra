# AI Infrastructure Engineer Take-Home Assignment

## Objective

This assignment evaluates your ability to work with **existing infrastructure** in a platform engineering role. You'll be given a working but problematic deployment of an ML service and asked to identify issues, propose improvements, and implement key fixes.

This reflects real-world work where you inherit infrastructure with technical debt, security gaps, and operational blind spots.

**Time expectation:** ~3 hours. We don't expect you to fix everything—prioritize what you consider most critical and document what you'd address given more time. You don't need to find every issue; focus on the ones that matter most and explain your reasoning.

---

## Scenario

An ML engineering team deployed a containerized image classification service six months ago. The service works but has accumulated technical debt and operational issues. You've been brought in to improve the infrastructure.

The service exposes:

- `GET /upload-url` – Returns a pre-signed URL to upload an image to S3
- `POST /start-job` – Starts an asynchronous classification job
- `GET /job/{id}/results` – Fetches job results

**Current state:** The service runs on AWS ECS Fargate with an RDS PostgreSQL database and S3 for image storage. The existing Terraform code is in the `terraform/` directory. A CI/CD pipeline exists in `.github/workflows/` but has known issues.

**Application assumptions:** The application container works correctly and exposes a `/health` endpoint for health checks.

---

## Known Issues (from the ops team)

The following problems have been reported:

1. **Cost:** AWS bill is higher than expected; the team suspects over-provisioned resources
2. **Deployments:** Updates require manual intervention; the CI/CD pipeline frequently fails
3. **Incidents:** Last month, the service went down for 2 hours because the database ran out of connections. The team suspects the ECS tasks may be opening too many connections, but has no visibility into the actual count
4. **Security audit:** A recent review flagged several concerns but the team hasn't had time to address them
5. **Observability:** When issues occur, it's difficult to determine root cause

---

## Your Tasks

### 1. Infrastructure Review & Fixes (Primary Deliverable)

Review the existing Terraform code in `terraform/` and:

- **Identify at least 5 issues** (security, reliability, cost, operational)
- **Fix at least 3 of them** in the Terraform code
- **Document your changes** with comments explaining the problem and solution

Focus on issues that would have the highest impact in a production environment.

**Note:** A fix can be a single-line change or a new resource—what matters is that it addresses a real problem correctly.

### 2. Architecture Document

Provide a written document (`ARCHITECTURE.md`) addressing:

- **Issues Found:** List all issues you identified, even those you didn't fix
- **Prioritization:** Explain why you chose to fix what you did
- **CI/CD Improvements:** How would you fix the deployment pipeline issues?
- **Monitoring Strategy:** What observability would you add to prevent the connection pool incident?
- **Security Remediation:** What security fixes are most urgent?
- **Trade-offs:** Any assumptions, risks, or decisions worth highlighting

---

## Existing Infrastructure

The project contains:

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml        # CI/CD pipeline
└── terraform/
    ├── main.tf               # Core infrastructure
    ├── ecs.tf                # ECS cluster and service
    ├── database.tf           # RDS PostgreSQL
    ├── storage.tf            # S3 bucket
    ├── variables.tf          # Input variables
    ├── outputs.tf            # Outputs
    └── terraform.tfvars.example
```

**Assumptions:**

- VPC, subnets, and base networking already exist (referenced by data sources)
- You have access to modify all resources in this Terraform configuration
- You have access to modify the CI/CD pipeline in `.github/workflows/deploy.yml`
- You can copy `terraform.tfvars.example` to `terraform.tfvars` if you want to validate syntax locally

---

## Evaluation Criteria

We're looking for:

1. **Issue identification:** Can you spot problems in existing infrastructure?
2. **Prioritization:** Do you focus on high-impact issues first?
3. **Practical fixes:** Are your changes production-ready and incremental?
4. **Operational thinking:** Do you consider monitoring, rollback, and failure modes?
5. **Communication:** Can you clearly explain problems and solutions?

---

## Submission

Submit a zip archive or Git repository containing:

- Modified Terraform files with your fixes
- `ARCHITECTURE.md` with your analysis and recommendations
- Any additional files you think are necessary

If using Git, ensure we have access or share a temporary invite.

---

## Questions?

If anything is unclear, make reasonable assumptions and document them. This mirrors real-world scenarios where requirements aren't always perfectly specified.
