# ML Classifier Service - Infrastructure Improvements

## Issues Identified

### Security Issues

1. RDS PostgreSQL instance was publicly accessible (`publicly_accessible = true`) : This exposed the database to the entire internet which is a major security issue.

2. Application security group allowed all inbound traffic from anywhere on any port (`0.0.0.0/0`, all protocols) : This could lead to serious attacks as we allow from anywhere, need to restrict.

3. Database password was stored in plain text Terraform variables and passed directly to ECS task definition : This would risk credential exposure in Git, Terraform state, and AWS console.

4. ECS task IAM role had overly broad permissions (`s3:*` and `rds:*` on all resources): This  violated least privilege principle, and was a major security issue.

5. S3 bucket had no server-side encryption at rest configured.

6. S3 bucket had no public access block : This risked the accidental public exposure via ACLs or policy mistakes.

7. There was no separation of ALB and ECS task security groups :  same group used for both, increasing risk.

### Reliability Issues

1. RDS was single-AZ (`multi_az = false`) : This allowed for a single point of failure for the entire database. Having it on a diff data centre would allow for data to be reliable.

2. No automated backups (`backup_retention_period = 0`) : This leads to a complete data loss possible on failure or corruption.

3. Deletion protection disabled (`deletion_protection = false`) : This provides no protection in case of accidental delete of the production database.

4. No performance insights or detailed logging export on RDS : This makes it difficult to diagnose connection pool exhaustion incident. This can lead to outages , as we have no way to monitor.

5. CloudWatch log group had no retention period : The  logs were being kept forever, It's not necessary it has high storage costs over time.

### Cost Issues

1. RDS instance class was `db.r5.2xlarge` : It's might be significantly over-provisioned for a typical image classification service. Need to add more observability and monitoring, but first reduce the resource and then scale if needed.

2. ECS tasks over-provisioned at 4 vCPU + 16 GB memory each :  It leads to high idle cost when traffic is low.

3. No log retention policy: As mentioned in reliability issue, the long-term log storage costs accumulate unnecessarily.

4. No S3 lifecycle policy: This is majorly an image inference service, there is no need to keep  user-uploaded images permanently, unnecessary storage cost growth.

### Operational Issues

1. Hardcoded plain-text database password in multiple places : Its difficult and insecure to rotate. 

2. CI/CD pipeline (deploy.yml) deploys to production(main) on every push to `develop` : This is  high risk of breaking production from dev work. Need seperate deployment and env for different stages.

3. CI/CD uses `-auto-approve` and no plan review step : Auto approve is fine for develop, but risky for production changes.

4. CI/CD uses `latest` image tag : In case of issues with deployed docker image, its difficult to rollback to known-good version. Major operational issue, can cause application downtime.

5. No environment awareness in Terraform (staging vs production) : The resources used must be different for develop and main, since any development change can affect the production otherwise.

## Issues Fixed

### Fix 1: Disable Public Access to RDS

**File:** `terraform/database.tf`

**Problem:** Database was publicly accessible, allowing internet connections.

**Solution:** Changed `publicly_accessible = true` to  `false`. The database is now only reachable from within the VPC.

**Trade-offs:** None as application still connects correctly via private subnets.

### Fix 2: Enable Multi-AZ and Automated Backups on RDS

**File:** `terraform/database.tf`

**Problem:** Single-AZ deployment and no backups , it has high risk of outage or data loss.

**Solution:**  
- `multi_az = true`  
- `backup_retention_period = 7`  
- `deletion_protection = true`

**Trade-offs:** around about 2× RDS cost increase (but this is offset by instance class reduction in the next fix ). This is Worth it for production reliability.

### Fix 3: Right-size RDS Instance Class

**File:** `terraform/database.tf`

**Problem:** `db.r5.2xlarge` looked like it was massively over-provisioned and risks very high cost.

**Solution:** Changed to `db.t3.large` (2 vCPU, 8 GB RAM). We can start here and monitor, if needed we can scale up.

**Trade-offs:** There is a possible performance risk if workload grows unexpectedly, but it can be  mitigated by monitoring. This saves cost, and allows human review and decision to scale.

### Fix 4: Enable Performance Insights on RDS

**File:** `terraform/database.tf`

**Problem:** We have No visibility into connection usage, slow queries, or wait events during outages. This also links to incident of last month (where  the service went down for 2 hours because the database ran out of connections. The team suspects the ECS tasks may be opening too many connections, but has no visibility into the actual count).

**Solution:** `performance_insights_enabled = true` + 7-day retention + CloudWatch log exports for PostgreSQL.

**Trade-offs:** This is a necessary and small additional cost in order to prevent application shutdowns.

### Fix 5: Right-size ECS Task Resources

**File:** `terraform/ecs.tf`

**Problem:** 4 vCPU + 16 GB per task ,Over provisioned and leads to high idle cost.

**Solution:** Reduced to 1 vCPU + 2 GB (`cpu = "1024"`, `memory = "2048"`). 

**Trade-offs:** We Monitor CPU/memory usage post-deployment; scale up if model inference is heavy.

### Fix 6: Set CloudWatch Log Retention

**File:** `terraform/ecs.tf`

**Problem:** Logs are kept forever. It leads to growing storage costs.

**Solution:** Added `retention_in_days = 30`.

**Trade-offs:** 30 days is sufficient for debugging an inference service. In case of issues, logs are only needed for short term monitoring and applying fixes, it can be  increased if compliance requires longer.

### Fix 7: Store DB Password in Secrets Manager

**Files:** `terraform/database.tf`, `terraform/ecs.tf`, `terraform/main.tf`

**Problem:** Plain-text password in variables, task definition, and state file.

**Solution:**  
- Created `aws_secretsmanager_secret` + random password  
- RDS uses `random_password.db_password.result`  
- ECS task references secret via `secrets` block  
- Limited the IAM permission to only this secret ARN

**Trade-offs:** Small cost. Requires Secrets Manager access in task role. This provides high security

### Fix 8: Apply Least-Privilege IAM Policy for ECS Task

**File:** `terraform/main.tf`

**Problem:** Wildcard permissions (`s3:*`, `rds:*` on `*`) are dangerous if container is compromised.

**Solution:** Restricted to:  
- Specific S3 actions on images bucket only  
- `secretsmanager:GetSecretValue` only on DB password secret  
- Removed unnecessary `rds:*` (as app uses standard PostgreSQL connection)

**Trade-offs:** None as permissions still cover all application needs.

### Fix 9: Restrict Application Security Group + Separate ALB Security Group

**File:** `terraform/main.tf`

**Problem:** App SG allowed all traffic from anywhere.

**Solution:**  
- Restricted ingress to port 8080 only from ALB security group  
- Created dedicated `aws_security_group.alb` for load balancer (allows 80/443 both http and https from internet)

**Trade-offs:** It improves security without breaking traffic flow.

### Fix 10: Secure S3 Bucket (Encryption, Public Block, Versioning)

**File:** `terraform/storage.tf`

**Problem:** There is no encryption at rest, no public access block. It could lead to user data being leaked.

**Solution:**  
- Added server-side encryption (AES256) 
- Added full public access block  
- Enabled versioning

**Trade-offs:** No trade offs as all are improvements with no downside.

### Fix 11: Add S3 Lifecycle to Expire Temporary Uploads

**File:** `terraform/storage.tf`

**Problem:** User-uploaded images kept forever . This leads to unnecessary cost growth.

**Solution:** This service is ML inference. The user uploads image gets answer. The life cycle for this is short. We don't need to store images indefinitely. Lifecycle rule expires objects after 14 days and aborts incomplete multipart uploads after 1 day.

**Trade-offs:** After 14 days, re-processing requires re-upload. This is acceptable as it is an  inference-only use case.

## Prioritization Rationale

I prioritized fixes in this order:

1. **Security first** (Fixes 1,7,8,9,10,11) — public DB, credential exposure, broad IAM, open security groups are immediate breach risks.

2. **Reliability next** (Fixes 2,3,4,6) — backups, Multi-AZ, deletion protection, and observability prevent outages and data loss (directly related to the connection pool incident).

3. **Cost optimization** (Fixes 3,5,6,11) — right-sizing DB/ECS and log/S3 lifecycle give large savings without compromising core functionality.

Security and reliability had highest impact. 
Cost fixes were taken in accordance to situation at hand, and aligned with known bill concerns.

## CI/CD Improvements

**Problems in current pipeline:**
- Deploys to production on push to both `main` **and** `develop` : The dev work can break prod.
- Uses `terraform apply -auto-approve` : There is  no review of changes, its okay for dev, but is not acceptable for production.
- Uses `latest` image tag : In case of flawed deployements. This makes it impossible to rollback cleanly.
- Uses outdated action versions (`checkout@v2`, `setup-terraform@v1`).
- Uses long-lived AWS access keys — security risk.
- No tests, linting, validation, or plan approval step.

**How I would fix them (changes already partially implemented):**
- Changed image tag to `${{ github.sha }}` : This allows for a reproducible and rollback-friendly image.
- Replaced `-auto-approve` with `terraform plan -out=tfplan` + `terraform apply tfplan` : A safer approach for production.

- **Recommended Improvements (not implemented due to time constraints):**
  - Split workflows: separate files for dev (`develop`) and production (`main`).
  - Use GitHub Environments for prod approval gates.
  - Switch to OIDC role assumption (remove access keys).
  - Add `terraform fmt --check`, `terraform validate`, `tflint`, and optional security scanning.
  - Use semantic versioning or git tags for images instead of SHA (for readability).

## Monitoring Strategy

**Given the DB connection exhaustion incident:**

**Metrics to monitor:**
- RDS: DatabaseConnections, CPUUtilization, FreeableMemory, ReplicaLag (Multi-AZ)
- ECS: CPUUtilization, MemoryUtilization, RunningTaskCount
- ALB: RequestCount, TargetResponseTime, HTTPCode_Target_5XX_Count
- CloudWatch Logs: error rate, connection refused messages

**Alerts to configure:**
- DatabaseConnections > 80% of max_connections then send SNS notification
- CPUUtilization > 80% sustained (RDS & ECS)
- Low FreeableMemory on RDS
- High 5xx errors on ALB

**Observability improvements:**
- Keep Performance Insights enabled (already done)
- Export RDS PostgreSQL logs to CloudWatch
- Consider Amazon CloudWatch Container Insights for ECS
- Dashboard in CloudWatch or Grafana showing connection trends + task scaling

## Security Remediation

**Most critical issues (in order):**
1. Publicly accessible RDS
2. Plain-text DB password in variables/task definition
3. Overly permissive ECS task IAM role
4. Open application security group (0.0.0.0/0 all ports)
5. No S3 encryption + no public access block


## Trade-offs and Assumptions

**Assumptions:**
- Application uses standard PostgreSQL connection (no need for `rds:*` IAM)
- Images are temporary (inference only), hence 14-day expiration is safe
- `db.t3.large` is sufficient starting point (can monitor and scale)
- Existing VPC/subnets are correctly configured and tagged
- No regulatory need for more than 30-day log retention or permanent image storage

**Trade-offs:**
- Multi-AZ roughly doubles RDS cost (offset by right-sizing)
- Smaller ECS/DB instances risk under-provisioning but it can be mitigated by monitoring
- 14-day image expiration means re-upload for old jobs , but its acceptable since this is an inference use case

**Remaining risks:**
- No auto-scaling yet : We have manual desired_count=3 could be inefficient, in case of high traffic or low usage situations
- No HTTPS on ALB — traffic unencrypted between client and ALB
- No staging environment separation — still risk if develop branch deploys bugs
