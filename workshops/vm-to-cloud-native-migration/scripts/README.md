# Acceptance gates for the VM → cloud-native migration

Three credential-free scripts that give Devin (and the facilitator) an executable feedback loop for
the [VM to Cloud-Native Migration](../../../modules/cloud-infrastructure/vm-to-cloud-native-migration.md)
module. No AWS account, no `terraform apply`.

| Script | What it does |
|---|---|
| `build-image.sh` | Assembles the two-repo build context that `docker/Dockerfile` requires (app repo's `frontend/` + `backend/`, hosting repo's `docker/`) and builds the production image. Nothing in either repo automates this, which is why the image is never built in CI. |
| `verify-deployment.sh` | Runs the image the way `user_data.sh` runs it on EC2 — root-owned data volume, same env vars, same port mapping — and asserts six runtime invariants. |
| `verify-terraform.sh` | `terraform init -backend=false` + `validate` on every stack, plus `fmt -check`. |

## The six gates

| Gate | Asserts | Catches |
|---|---|---|
| G1 | The container reaches a healthy state on a root-owned data volume | `SQLITE_CANTOPEN` crash-loop: `user_data.sh` creates `/opt/app/data` as root, the image runs as uid 1001 |
| G2 | `GET /health` returns 200 | Basic liveness / port mapping |
| G3 | A client can be written and read back | Schema drift: the forked `docker/overrides/database/init.js` predates the `clients.department` and `clients.email` columns the app queries, so `GET /api/clients` 500s |
| G4 | Data survives a container restart | Persistence actually wired to the volume/datastore |
| G5 | The application process is not root (checked on the process, not the image's exec user, so drop-privileges entrypoints pass) | Container hardening regressions |
| G6 | SIGTERM is handled and the container exits promptly | Rolling deploys that hang or drop in-flight requests |

## Usage

```bash
./build-image.sh                                  # defaults to ~/repos/{app_timesheet,hosting-client-timesheet-app}
./verify-deployment.sh timesheet:local 8080
./verify-terraform.sh
```

Verified baselines on a clean machine:

- the image as shipped today → **0 of 6 gates pass** (aborts at G1, crash-loop)
- a corrected image (single-source `init.js`, entrypoint that chowns `/app/data` and drops to uid 1001) → **6 of 6 pass**

## Requirements

Docker, Node 20+, Terraform CLI, passwordless `sudo` (G1 recreates a root-owned data directory), and
a free host port (default 8080).

If the migration replaces SQLite with a managed datastore, point the container at it without editing
the script:

```bash
EXTRA_RUN_ARGS="--network timesheet_default -e DATABASE_URL=postgres://..." ./verify-deployment.sh timesheet:local
```
