# VM to Cloud-Native Migration

## Repositories

- [hosting-client-timesheet-app](#hosting-client-timesheet-app) (infrastructure, primary)
- [app_timesheet](#hosting-client-timesheet-app) (application, required)

---

## Challenge

Take a single-VM, hand-deployed application and move it to a managed, containerized platform — the
full chain, in one session: **analyse the existing infrastructure → translate host assumptions into
cloud services → migrate the deployment pipeline → containerize and orchestrate → prove it works**.

This is the migration challenge with a real *before* state. The timesheet app runs on one EC2
instance in the default VPC: a `user_data.sh` script installs Docker, writes `/opt/app/deploy.sh`,
and registers a `oneshot` systemd unit that does `docker pull && docker run`, persisting SQLite to a
host path. Deployment for that path has no pipeline at all, and the image is never built in CI —
so it contains defects that no unit test can see.

## Target Outcomes

- A written infrastructure analysis naming the host-level couplings and the drift between the two repos
- Host assumptions translated to managed services (durable datastore, config/secrets, ingress, logs)
- A CI/CD pipeline that builds, scans, deploys, and health-gates the container path
- Container orchestration manifests (ECS task definition / Kubernetes + Helm) with probes, resource
  limits, and rolling deploys
- The acceptance gates in [`workshops/vm-to-cloud-native-migration/scripts`](../../workshops/vm-to-cloud-native-migration/scripts)
  go from red to green
- PRs in both repos, plus a reusable playbook for the next service

## What Participants Will Learn

- How Devin discovers infrastructure coupling that is invisible in either repo alone
- Why "all tests pass" is not the same as "it works in the target environment"
- How to give Devin an executable feedback loop for infrastructure work without cloud credentials
- How one migrated service becomes a playbook that child sessions run against the rest of the fleet

## Devin Features Exercised

- Multi-repo analysis (Ask Devin, DeepWiki)
- IaC comprehension and generation (Terraform, Helm/ECS)
- CI/CD pipeline authoring
- Containerization and runtime debugging against a locally reproduced target
- Playbooks and child sessions for parallel fan-out

## Difficulty

Advanced

## Estimated Time

75 minutes (45-minute short form: Acts 1-3 only)

---

## <a id="hosting-client-timesheet-app"></a>hosting-client-timesheet-app + app_timesheet

**Repositories:**
[hosting-client-timesheet-app](https://github.com/Cognition-Partner-Workshops/hosting-client-timesheet-app),
[app_timesheet](https://github.com/Cognition-Partner-Workshops/app_timesheet)

### What the starting state actually contains

Verified by cloning both repos, building the image, and running it the way `user_data.sh` does:

| # | Finding | Where |
|---|---------|-------|
| 1 | Production image ships **forked copies of two application files** (`server.js`, `database/init.js`) that are overlaid at build time | `docker/overrides/`, `docker/Dockerfile` |
| 2 | The forked schema predates the app's `clients.department` / `clients.email` columns, and it is created with `CREATE TABLE IF NOT EXISTS` with no migrations — **`GET /api/clients` returns 500 in production** while all 161 unit tests pass | `docker/overrides/database/init.js` vs `backend/src/routes/clients.js` |
| 3 | The image runs as uid 1001 but `user_data.sh` creates `/opt/app/data` as root, so **SQLite fails with `SQLITE_CANTOPEN` and the container crash-loops on a fresh instance** | `user_data.sh`, `docker/Dockerfile` |
| 4 | The build context spans two repos (`frontend/` + `backend/` from the app repo, `docker/overrides/` from the hosting repo); nothing automates it, so the image is never built in CI | `docker/Dockerfile` |
| 5 | The README documents a `.github/workflows/deploy.yml` EC2 pipeline that **does not exist** — only `deploy-serverless.yml` is present, and it checks out a repo name (`client-timesheet-app`) that does not exist in the org | `README.md`, `.github/workflows/` |
| 6 | Two divergent target architectures coexist undocumented: `terraform/infrastructure` (EC2 + SQLite on EBS) and `terraform/serverless` (Lambda + DynamoDB + S3 + API Gateway) | `terraform/` |
| 7 | Pet-server topology: `aws_default_vpc`/`aws_default_subnet`, single AZ, Elastic IP instead of a load balancer, SG open to `0.0.0.0/0` on 80 and 443 with no TLS terminator, `create_before_destroy` on an instance holding the only copy of the data | `terraform/infrastructure/main.tf` |
| 8 | Deploys are `docker stop` → `docker run` over SSM: downtime every release, health check only *after* cutover, no rollback | `user_data.sh`, `deploy-serverless.yml` |
| 9 | Least-privilege bug: an `EC2DescribeAll` statement grants `ec2:DescribeInstances` on `*`, negating the tag-scoped statement above it | `terraform/bootstrap/main.tf` |
| 10 | `helmet` is configured with `strictTransportSecurity: false` and the rate limiter runs without `trust proxy` — both break behind an ALB | `docker/overrides/server.js` |

Findings 2 and 3 are the demo's centre of gravity: two production-only failures that the test suite
structurally cannot catch, because tests run the app's own in-memory SQLite.

### Step 1: Paste into Devin

Run as three prompts so the analysis is reviewable before any code is written.

**Act 1 — analyse (no code changes):**

> Analyse how `hosting-client-timesheet-app` deploys `app_timesheet` today. Read the Terraform in
> all three stacks, `user_data.sh`, `docker/Dockerfile` and `docker/overrides/`, and the GitHub
> Actions workflows. Do not change any code yet. Produce a migration assessment covering: (1) every
> host-level assumption the application depends on, (2) where the same file exists in both repos and
> has diverged, (3) which of the two Terraform stacks the documentation and the pipelines actually
> agree on, (4) what breaks on a fresh instance, and (5) an ordered migration plan to a managed
> container platform with the risk of each step. Post the assessment as the PR description of a
> docs-only PR.

**Act 2 — reproduce and fix the target-only defects:**

> Build the production image with `workshops/vm-to-cloud-native-migration/scripts/build-image.sh`
> and run `verify-deployment.sh` against it. It fails. Diagnose each failure against the real cause,
> then make all six gates pass. Constraints: one source of truth for the application code — do not
> keep forked copies under `docker/overrides/`; the schema the container creates must match the
> schema the application queries, with a migration path for existing data; keep the container
> non-root. Re-run the gates and paste the before/after output in the PR.

**Act 3 — translate, containerize, and build the pipeline:**

> Migrate the EC2 deployment to ECS Fargate behind an ALB, in a new `terraform/ecs` stack: private
> subnets, HTTPS listener, target-group health checks on `/health`, rolling deploys with circuit
> breaker and rollback, task role instead of an instance profile, SQLite replaced with a managed
> datastore (justify RDS Postgres vs DynamoDB in the PR), configuration through task-definition env
> and Secrets Manager, and logs to CloudWatch. Add a `.github/workflows/deploy-ecs.yml` that builds
> the image, runs the app's jest suite, scans the image, pushes to ECR, deploys, and gates on a
> post-deploy health check with automatic rollback. `terraform validate` and
> `verify-terraform.sh` must pass, and `verify-deployment.sh` must stay green. Open PRs in both repos.

### Step 2: Research with Ask Devin

- *"In hosting-client-timesheet-app, which files are copies of files in app_timesheet, and how have they diverged?"*
- *"Which Terraform stack is actually deployed — what do the workflows and the README each assume?"*
- *"What would break if the EC2 instance were replaced right now?"*
- *"What is the cheapest target that removes the single point of failure — ECS Fargate, EKS, or the existing serverless stack?"*

### Step 3 (Optional): Read the DeepWiki

Open the DeepWiki for both repos side by side and trace one request from the Elastic IP to the
SQLite file. Ask it what the blast radius of an instance replacement is.

### Step 4 (Optional): Review & Give Feedback

- Review the ECS stack — is anything still single-AZ? Is the datastore backed up?
- Comment asking for a `PodDisruptionBudget`/`deployment_circuit_breaker` equivalent, autoscaling on
  CPU and request count, and a documented rollback runbook.
- Comment asking Devin to turn the whole migration into a playbook, then fan it out with child
  sessions to `onboarding-diary-app`, `ev-compare`, `Tutor-Bank`, and `prototype-1`.
