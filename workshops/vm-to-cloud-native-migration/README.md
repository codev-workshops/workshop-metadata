# Workshop: VM to Cloud-Native Migration

## Overview

| | |
|---|---|
| **Focus** | Single-VM, hand-deployed app → managed container platform: analysis, translation, CI/CD, containerization, validation |
| **Duration** | 75 min demo / 90-120 min hands-on |
| **Audience** | Platform engineering, DevOps, cloud architects, infrastructure leadership |
| **Key Modules** | [VM to Cloud-Native Migration](../../modules/cloud-infrastructure/vm-to-cloud-native-migration.md) |
| **Repos** | `hosting-client-timesheet-app`, `app_timesheet` |

## Workshop Narrative

Most migration demos start from a repo that is already cloud-native, so the "analysis" step is
theatre. This one does not. The timesheet app really does run on one EC2 instance in the default
VPC, deployed by a shell script that a `oneshot` systemd unit invokes over SSM, with SQLite on a host
path — and because the container image is never built in CI, it carries **two defects that only
appear in the target environment**:

1. On a fresh instance the container cannot open its database (`SQLITE_CANTOPEN`) — `user_data.sh`
   creates `/opt/app/data` as root, the image runs as uid 1001.
2. `GET /api/clients` returns **500 in production** — the hosting repo keeps a *forked copy* of the
   app's `database/init.js` whose `clients` table predates the `department` and `email` columns the
   application queries, created with `CREATE TABLE IF NOT EXISTS` and no migrations.

All 161 unit tests pass, because they run the app's own in-memory SQLite. That is the entire
argument for the migration approach in one screen: **you cannot validate a migration without the
target environment, and you cannot see this coupling by reading either repo alone.**

## The Arc

Five acts. Each ends with something objective on screen.

| Act | Time | What the audience sees |
|-----|------|------------------------|
| 0 — The setup | 5 min | Two repos, green test suite, green `terraform validate`. Nothing looks wrong. |
| 1 — Analysis | 15 min | Devin maps the deployment and names the couplings, the cross-repo drift, and the two-architecture ambiguity. Docs-only PR. |
| 2 — The proof | 15 min | The image is built and run the way EC2 runs it. `verify-deployment.sh` → **0 of 6 gates pass**. Devin diagnoses and fixes; gates go green. |
| 3 — Translation + pipeline | 25 min | ECS Fargate + ALB + managed datastore + Secrets Manager Terraform, and a build → test → scan → deploy → health-gate → rollback workflow. |
| 4 — At scale | 15 min | The migration becomes a playbook; child sessions run it against four more services in parallel. |

### Act 0 — The setup (5 min)

Show, in this order:

```bash
cd ~/repos/app_timesheet/backend && npx jest          # 161 passed
~/repos/workshop-metadata/workshops/vm-to-cloud-native-migration/scripts/verify-terraform.sh
```

Then say: *"Green tests, valid Terraform, a Dockerfile, an ECR repo, OIDC into AWS. By every signal
this team has, this service is fine. It is not."*

### Act 1 — Analysis (15 min)

Paste Act 1's prompt from the
[module](../../modules/cloud-infrastructure/vm-to-cloud-native-migration.md#step-1-paste-into-devin).
While Devin works, use Ask Devin live on the same repos so the room sees both the deep session and
the instant answers.

**Findings to make sure land** (all verified — see the module's findings table): forked files in
`docker/overrides/`, a documented `deploy.yml` pipeline that does not exist, a workflow that checks
out a repo name that does not exist in the org, two divergent Terraform stacks, `aws_default_vpc`,
single AZ, EIP-instead-of-ALB, `0.0.0.0/0` on 443 with no TLS, `create_before_destroy` on the
instance that holds the only copy of the data, and an `ec2:DescribeInstances` statement on `*` that
negates the tag condition above it.

Keep this act **docs-only**. Reviewing a migration plan before code is the practice you want the
audience to copy.

### Act 2 — The proof (15 min)

This is the act people remember.

```bash
cd ~/repos/workshop-metadata/workshops/vm-to-cloud-native-migration/scripts
./build-image.sh                       # assembles the two-repo build context nothing else automates
./verify-deployment.sh timesheet:local  # SUMMARY: 0 passed, 1 failed (crash-loop)
```

Then hand the failure to Devin (Act 2 prompt). Two rules make the fix real rather than cosmetic:
**one source of truth for application code** (delete `docker/overrides/`, upstream the file-based
SQLite support into `app_timesheet`) and **the schema the container creates must match the schema the
app queries**, with a migration for existing rows.

Expected end state, live on screen:

```
PASS  G1 container stays running on a root-owned data volume
PASS  G2 /health returns 200
PASS  G3 client can be written and read back (runtime schema matches app code)
PASS  G4 data survives a container restart
PASS  G5 application process does not run as root (user=1001)
PASS  G6 handles SIGTERM and exits cleanly
SUMMARY: 6 passed, 0 failed
```

> Both states are pre-verified on a clean machine: the shipped image scores 0/6, and a corrected
> image scores 6/6. If the room wants to see the target state before Devin gets there, the fix is a
> single-source `init.js` plus an entrypoint that chowns `/app/data` and drops to uid 1001.

### Act 3 — Translation and pipeline (25 min)

Paste Act 3's prompt. While it runs, narrate the translation table the audience actually cares about:

| Legacy assumption | Cloud-native target | Why |
|---|---|---|
| SQLite file on EBS at `/opt/app/data` | RDS Postgres (or DynamoDB) | Data outlives the compute; instance replacement stops being a data-loss event |
| `docker run` from a systemd `oneshot` unit | ECS Fargate service (or Deployment + Helm) | Scheduler owns restarts, rollouts, and capacity |
| Elastic IP on one instance | ALB + target group + HTTPS listener | Multi-AZ, TLS termination, health-gated cutover |
| `aws_default_vpc` / `aws_default_subnet` | Explicit VPC, private subnets, NAT | The default VPC is not a design |
| Config baked into `deploy.sh` | Task definition env + Secrets Manager | Rotatable, auditable, no rebuild to change config |
| `docker logs` over an SSM session | CloudWatch Logs + `/health` metrics | Debuggable without shelling into a box |
| Instance profile with ECR pull | Task role, least privilege, no `Resource: "*"` | Blast radius |
| Health check *after* cutover | Deployment circuit breaker + rollback | Failed deploys stop being outages |

**Non-negotiable in the PR:** `terraform validate` clean, `verify-terraform.sh` clean,
`verify-deployment.sh` still 6/6, and the pipeline gating deploy on tests *and* a post-deploy health
check with automatic rollback.

### Act 4 — At scale (15 min)

One migrated service is a case study; the playbook is the product.

> Turn what you just did into a playbook for migrating a single-VM Dockerized service to ECS Fargate.
> Include: the analysis questions to ask, the drift checks (files duplicated across repos, docs
> referencing pipelines that do not exist), the acceptance gates that must pass before opening a PR,
> the translation table for host assumptions, and the PR structure (docs-only assessment first, then
> code). Then start child sessions that apply it to `onboarding-diary-app`, `ev-compare`,
> `Tutor-Bank`, and `prototype-1`, one session per service, each opening its own PR with the gate
> output in the description.

Show the child sessions running side by side, then close on the review queue: *four PRs, one
reviewer, one standard.*

## Best Practices to Call Out (the part that makes this repeatable)

1. **Reproduce the target locally before changing anything.** Cloud credentials are not required to
   catch the two worst bugs here — a container run the way production runs it caught both.
2. **Write the acceptance gates before the migration.** `verify-deployment.sh` is 120 lines of bash
   and it is what turns "Devin migrated it" into "the migration is provably equivalent." Gates first,
   code second.
3. **Assert on the *runtime* contract, not the code.** Gate G3 writes a record and reads it back;
   that is what caught a schema drift no unit test could see.
4. **Docs-only PR first.** Land the assessment and plan as a reviewable artifact, then the code. It
   is also how you get a second opinion before spending a change window.
5. **Kill the forks.** Every file duplicated across an app repo and an infra repo will drift. Making
   this an explicit analysis question finds problems in almost every real estate.
6. **Treat outdated docs as findings, not noise.** A README documenting a pipeline that does not
   exist tells you which deployment path is actually maintained.
7. **Migrate one service by hand-holding, then codify.** Playbook after the first success, not
   before — the first migration is where you learn what the playbook must say.
8. **Fan out in waves, not all at once.** One service per child session, one PR per service, same
   gates, same reviewer. Batch by similarity (runtime, datastore, ingress) so a single playbook fits.
9. **Make CI the standard-enforcer.** Once the gates exist, run them in CI on every service so
   migrated services cannot regress to pet-server patterns.
10. **Keep a decision log in the PR.** RDS vs DynamoDB, Fargate vs EKS — the reasoning is what a
    platform team reuses on the next 40 services.

## Repos Required

- [ ] `hosting-client-timesheet-app`
- [ ] `app_timesheet`
- [ ] Fan-out targets (Act 4): `onboarding-diary-app`, `ev-compare`, `Tutor-Bank`, `prototype-1`

## Prerequisites on Devin's Machine

| Requirement | Check |
|---|---|
| Docker | `docker version` |
| Node 20+ | `node -v` |
| Terraform CLI | `terraform version` (not preinstalled by default — add it to the blueprint) |
| Passwordless sudo | `sudo -n true` (the gate script recreates a root-owned data dir) |
| Free port 8080 | `ss -lntp \| grep 8080` |
| AWS credentials | **Not required.** Only needed if you intend to `terraform apply` live. |

Pre-flight, ~5 minutes before the demo:

```bash
cd ~/repos/workshop-metadata/workshops/vm-to-cloud-native-migration/scripts
./verify-terraform.sh                                   # 3 stacks valid, fmt findings expected
./build-image.sh && ./verify-deployment.sh timesheet:local   # expect 0 passed — this is the baseline
docker image prune -f
```

## Timing Variants

| Duration | Acts |
|---|---|
| 30 min (executive) | 0, 1, 2 — analysis plus the 0/6 → 6/6 flip |
| 45 min | 0-2 plus the translation table narrated from Act 3's plan |
| 75 min (recommended) | 0-4 |
| 2 hours (hands-on) | 0-4 with participants running Acts 2 and 3 themselves |

## Risks & Fallbacks

| Risk | Mitigation |
|---|---|
| Live `terraform apply` fails on someone's AWS account | Never apply live. `validate` + `plan` are the gate; the ECS stack is reviewed as code. |
| Devin proposes the existing serverless stack instead of ECS | Fine — it is a defensible target. Have it justify the choice in the PR; the gates are unchanged. |
| Act 3 overruns | Ship Act 3 as a PR under review and switch to Act 4; the fan-out is the closing message anyway. |
| Room asks "was this planted?" | Show the history: the fork was written once (`ab70a89 Add AWS infrastructure as code with GitHub Actions CD`) and the app moved on afterwards (`a35868c Add department and email fields to client creation`, `b40be91 fix: Handle multiple closeDatabase calls safely` — the latter is also missing from the forked copy). Ordinary history, and that is the point. |
| Port 8080 or a stale container in use | `docker rm -f timesheet-acceptance` and pass a different port: `./verify-deployment.sh timesheet:local 8090`. |

## Key Takeaways

- **"Green CI is not a migration signal."** Two production-breaking defects, 161 passing tests.
- **"Devin found coupling that spans two repositories."** Neither repo is wrong on its own.
- **"The feedback loop is the deliverable."** Gates written once, reused by every child session.
- **"One service becomes a playbook; the playbook becomes a fleet."**
