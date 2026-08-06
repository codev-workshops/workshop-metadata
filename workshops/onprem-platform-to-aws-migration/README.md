# On-Prem Platform to AWS Migration (IvozProvider)

**Duration:** 90 min · **Difficulty:** Advanced · **Audience:** Cloud/Platform/Infrastructure
engineering, SRE, telco and any team with a Debian/systemd/Jenkins estate

Covers the full *Infra & Platform Migrations* chain — infrastructure analysis → cloud-native
translation → CI/CD migration → containerization → validation loops → parallel execution — on a
real distributed platform rather than a single app on a VM.

- Prompt set: [`prompts.md`](prompts.md) — four prompts (analyse → plan → feedback loop → execute), then two to scale
- Module: [`../../modules/cloud-infrastructure/onprem-platform-to-aws-migration.md`](../../modules/cloud-infrastructure/onprem-platform-to-aws-migration.md)
- Opening proof script: [`scripts/verify-topology.sh`](scripts/verify-topology.sh)

## Repositories

| Repo | Role |
|---|---|
| `ivozprovider` | The platform. Kamailio + Asterisk + rtpengine + Percona MySQL + Redis Sentinel + CGRateS + PHP/Symfony REST API + 4 React portals + 9 microservices, shipped as Debian packages configured by debconf prompts, built by Jenkins. |

## Prerequisites

Docker, Terraform CLI, Node 20+, ~90 s for the opening proof. An AWS sandbox account is required
only if you intend to `apply`; prompts 1–3 need no cloud access at all.

---

## Why this platform

The deck's three stall reasons are all present in their strongest form:

| Deck claim | Reality in this repo |
|---|---|
| implicit dependencies — local paths, network shares, host configs | Service discovery is a **BIND zone on every node** (`users`, `trunks`, `data`, `cache`, `storage`, `logs`, `jobs`, `hep`), whose A records are rewritten by `sed` in a postinst. Shared state is a `chmod 777` directory. DB credentials are `sed`-ed into `/etc/odbc.ini`. |
| no testing without the target | `docker-compose.yml` has **no Kamailio, no Asterisk, no rtpengine** — the telephony plane cannot be run locally today, so nothing can be compared before/after. |
| scale defeats manual effort | 25 Debian packages, 13 systemd units, 4 host profiles, 9 microservices, 155 tables + 10 views, 124 Doctrine migrations, 7,872 files. |

And it has real-time media, which forces genuine architecture decisions instead of "containerize it
and add an ALB".

---

## Verified starting state

Run this first; it takes about 90 seconds and needs only Docker:

```bash
./scripts/verify-topology.sh ~/repos/ivozprovider
```

```
BASE TABLE  155        VIEW  10

source                value                  label
ApplicationServers    127.0.0.1              as001
ProxyUsers            127.0.0.1              proxyusers
ProxyTrunks           127.0.0.1              proxytrunks
kam_dispatcher        sip:127.0.0.1:6060     as001
kam_rtpengine         udp:127.0.0.1:22223    Default rtpengine set
```

**The platform's service registry is its own database.** A Perl script renders those rows into host
config at install time:

```perl
# profiles/proxy/etc/kamailio/autoconf
my $sql = "SELECT id, name, ip, advertisedIp FROM $mysql_table ORDER BY id ASC";
say $FILE "listen=udp:$ip:SIP_PORT advertise $advertised:SIP_PORT";
```

So the platform **cannot autoscale** without either stable per-node addresses or new code that
registers and deregisters nodes in the database. That is the migration's defining decision, and it
is invisible from the infrastructure code alone.

The same script also prints every address column, split by who owns the value. Six describe our
infrastructure; twelve describe **carrier and customer endpoints** (`CarrierServers.ip`,
`DDIProviderAddresses.ip`, `kam_trusted.src_ip`, `Friends.ip`, `ResidentialDevices.ip`,
`RetailAccounts.ip`, `Companies.ipFilter`, …). Changing public IPs therefore breaks third-party
ACLs: the migration is a commercial coordination exercise, not only a Terraform change.

### Host-level assumption inventory

| # | Assumption | Evidence |
|---|---|---|
| 1 | Per-node BIND server is the service directory | `profiles/data/etc/bind/db.ivozprovider.local` + `ivozprovider-profile-data.postinst` |
| 2 | Configuration comes from **interactive debconf prompts** (30 templates) | `debian/*.templates`, `debian/*.postinst` |
| 3 | DB credentials in plaintext host files | `profiles/as/etc/odbc.ini.ivozprovider` (`Password = changeme`) |
| 4 | `GRANT ALL ON *.*` to `root@%`, `kamailio@%`, `asterisk@%` with `mysql_native_password` | `ivozprovider-profile-data.postinst` — **not permitted on RDS** |
| 5 | MySQL tuned by editing `/etc/mysql/conf.d/*` (`bind-address`, `wait_timeout=604800`, charset handshake) | `profiles/data/etc/mysql/conf.d/ivozprovider.cnf` — must become a parameter group |
| 6 | Shared FS `/opt/irontec/ivozprovider/storage`, `chmod 777`: recordings, locutions, voicemail, invoices, **JWT private keys** | `ivozprovider-profile-common.postinst`, `ivozprovider-web-rest.postinst` |
| 7 | Media relay bound to the node's **public IP**, UDP 13000–19000, control on private IP:2223 | `ivozprovider-profile-proxy.postinst` + templates |
| 8 | Asterisk reads config from MySQL over **ODBC realtime** | `asterisk/config/extconfig.conf`, `res_odbc.conf` |
| 9 | Kamailio **DMQ** replicates state to `sip:users.ivozprovider.local:5060` | `profiles/proxy/etc/kamailio/autoconf` |
| 10 | Redis is **Sentinel** (`mymaster`, 26379) | `docker/redis/sentinel.conf` |
| 11 | Every binary comes from one external apt repo, `packages.irontec.com` (54 packages in `tempest/main`, incl. a backported `libssl1.1`) | `tests/docker/Dockerfile` |
| 12 | Dev DB is MariaDB 10.8, prod is Percona 8.0, dump made by MySQL 8.0.25 | `docker/mariadb/Dockerfile` vs `README.md` |

### CI today

`Jenkinsfile`, 780 lines, `@Library('jenkins-pipeline-library@0.0.2')`. A GitHub Actions migration
must not silently drop: Jira field updates and PR-title rewriting, Mattermost notifications, a
**homemade content-hash test cache** (`cached_pipelines.txt`, `MAX_HASHES = 400`), commit-tag/label
conditional stages, the `library/bin/test-*` suites, schema tests against a Percona 8.0 container,
four portal lint/i18n/build jobs, Cypress/Pact against a throwaway httpd image,
`dpkg-buildpackage -b`, StackHawk DAST, and functional-review + mergeability gates. It also relies
on `reuseNode` and `JENKINS_HOME` state that ephemeral runners do not have.

### The feedback loop already in the repo, unused

`tests/bbs/` — **48 YAML black-box SIP scenario files** ([irontec/bbs](https://github.com/irontec/bbs)):
IVRs, voicemail, hunt groups, conferences, pickup groups, call forwarding, blind transfer,
conditional locks, DDI in/out, retail and residential brands.

```yaml
# tests/bbs/2100-test-voicemail.yaml
scenarios:
  - name: call from alice to voicemail
    sessions:
      - alice:
          - call: { dest: "*93", credentials: *alice_cred }
          - waitfor: CONFIRMED
          - dtmf: "#"
          - waitfor: DISCONNCTD
```

It emits JUnit XML. Making these run against both the legacy stack and AWS is the migration's
acceptance test.

---

## Target architecture — and the decisions Devin must justify

Migrate **per plane**, not per host profile.

| Plane | Today | Target | Constraint |
|---|---|---|---|
| Data | Percona 8.0 on `data` | Aurora MySQL 8.0, parameter group replacing `conf.d`, Secrets Manager | `GRANT ALL ON *.*` / `mysql_native_password` must be reworked |
| Cache | Redis Sentinel | ElastiCache Redis | clients must drop Sentinel discovery |
| Storage | `chmod 777` share | S3 for recordings/locutions/invoices, EFS access point only for the voicemail spool, Secrets Manager for JWT keys | never recreate a world-writable share |
| Directory | BIND zone per node | Route 53 private hosted zone + Cloud Map | keep the same names so config diffs stay small |
| Web/API | Apache/PHP on `portal` | ECS Fargate + ALB (HTTPS, `/health`), CloudFront + S3 for bundles | stateless once storage and JWT keys move |
| Workers (9) | systemd units | ECS services; schedulers → EventBridge Scheduler | the child-session fan-out set |
| Asterisk | `as` node, PJSIP realtime ODBC | ECS on EC2 / EKS, awsvpc, registered in `ApplicationServers` + `kam_dispatcher` | needs a stable address per AS |
| Kamailio | listeners generated from DB | EC2 with one EIP per node, `advertise` = EIP, DMQ, `usrloc` in DB | an NLB cannot preserve SIP registration/DMQ semantics |
| Media | rtpengine on public IP, UDP 13000–19000 | EIP per media node, **no load balancer**; scale via `kam_rtpengine` rows | an NLB listener is a single port; 6000-port UDP ranges rule LBs out |
| CI/CD | Jenkins + shared library | GitHub Actions, OIDC, ECR, `actions/cache` + path filters | ephemeral runners only |
| Observability | `logs`/`hep` hosts, Homer | CloudWatch + OpenSearch for HEP capture, exporters → Managed Prometheus/Grafana | SIP capture is how VoIP is debugged; don't drop it |

**Explicit non-goal for the first waves:** do not modernize the signaling/media plane onto Kubernetes with a
service mesh. Containers earn their place on the web, worker and (carefully) Asterisk planes first.

---

## Feedback loop — build this before migrating anything hard

| Layer | Gate | How |
|---|---|---|
| L0 | static + unit | `library/bin/test-phpspec`, `test-phpstan`, `test-psalm`, `test-codestyle`, `test-phplint`; portal `test-lint`/`test-i18n`/`test-build` — all already exist |
| L1 | **legacy baseline stack** | extend `docker-compose.yml` with `kamailio-users`, `kamailio-trunks`, `asterisk`, `rtpengine` + seeded DB. *Does not exist yet; highest-value thing Devin builds first* |
| L2 | **call-flow equivalence** | `tests/bbs/entrypoint.sh` → JUnit XML, run against L1 and AWS; diff pass/fail sets |
| L3 | API + UI contracts | `tests/rest/postman-api-tests.json` (newman), Cypress/Pact per portal |
| L4 | **data equivalence** | `pt-table-checksum` (already in the CI image) Percona↔Aurora; row-by-row diff of `BillableCalls`, `kam_users_cdrs`, `Invoices` after a parallel-run window |
| L5 | infra + supply chain | `terraform validate`/`plan`, `tflint`/`checkov`, image scan, `dpkg-buildpackage -b` still green |

### Acceptance gates for every migrated component

```
G1   terraform validate + plan clean; no replacement of stateful resources
G2   passes its health check from a cold start in an empty environment
G3   no plaintext credential in any config file or image layer
G4   non-root process; no world-writable shared path
G5   the bbs call-flow suite passes against the migrated stack
G6   CDRs match the legacy run (count + per-call duration/billing fields)
G7   pt-table-checksum reports zero diffs for migrated tables
G8   registration survives node replacement (usrloc/dispatcher rows converge)
G9   media flows both ways after failover; MOS fields populated in kam_users_cdrs
G10  rolling deploy with automatic rollback; no in-call drop (or documented drain)
G11  logs and SIP capture (HEP) reach CloudWatch/OpenSearch
G12  every legacy debconf prompt has a declared cloud equivalent
```

---

## Waves (dependency-ordered, risk-ascending)

| Wave | Scope | Risk | Parallelism |
|---|---|---|---|
| 0 | VPC, Route 53 PHZ, ECR, OIDC role, Secrets Manager, TF state, Actions skeleton | Low | — |
| 1 | Aurora + parameter group + scoped grants, `initial.sql` + 124 migrations, ElastiCache, S3/EFS, JWT keys | Medium | — |
| 2 | REST API + 4 portals on ECS/ALB/CloudFront | Low | 5 services |
| 3 | 9 microservices / systemd units → ECS + EventBridge Scheduler | Low | **9 child sessions** |
| 4 | Asterisk AS: image, realtime ODBC, FastAGI, self-registration | High | per-AS |
| 5 | Kamailio + rtpengine: EIPs, `advertise`, DMQ, node registrar replacing `autoconf` | **Highest** | users/trunks |
| 6 | Jenkins → Actions, observability, per-brand traffic cutover | Medium | per-suite |

**Cutover:** run AWS in parallel; move one brand, then one company at a time by pointing its SIP
domain and DDIs at the new proxies; keep Aurora as a replica of Percona until the flip. Rollback is
DNS plus reverting `kam_dispatcher`/`ProxyUsers` rows. Freeze `advertisedIp` values until carrier
ACL updates are confirmed.

---

## Access Devin needs

| Need | How |
|---|---|
| AWS | dedicated sandbox account; OIDC role for CI, session role for Devin — never production |
| Terraform state | S3 + DynamoDB lock (wave 0) |
| ECR | push/pull via OIDC |
| `packages.irontec.com`, packagist, npm | must be reachable (verified reachable from a standard Devin box) |
| Database | anonymized dump or the repo fixtures — never production tenant/carrier data |
| Jira / Mattermost | only if the CI migration must keep notifications live |

No SIP trunk is needed: the bbs suite exercises calls inside the stack. Real carrier testing stays a
human step.

## What Devin must escalate rather than decide

- Which public IPs are preserved (BYOIP/EIP) versus renegotiated with carriers and tenants.
- Schema changes to billing tables (`BillableCalls`, `Invoices`, CDRs).
- Regulatory/geographic placement of recordings and CDRs.
- Emergency-call (112/911) routing behaviour.
- The cutover window per brand.

---

## Run of show (90 min)

| Act | Min | On screen |
|---|---:|---|
| 0 | 5 | `docker compose config` is valid — then point out there is no Kamailio, Asterisk or rtpengine in it. "You cannot run the product." |
| 1 | 10 | `scripts/verify-topology.sh`. Topology rows, then the address columns split ours/theirs. "Your topology is customer data." |
| 2 | 20 | Prompt 1 (Analyse) live as Ask Devin; prompt 2 (Plan) produces the docs-only migration plan PR. |
| 3 | 20 | Prompt 3: Devin builds the legacy baseline stack and gets the bbs call-flow suite running. Narrate this as the unlock. |
| 4 | 20 | Prompt 4: Aurora + ECS/ALB for the web plane, gates pasted in the PR. |
| 5 | 15 | Prompts 5 and 6: playbook, then child sessions fanning out across the 9 microservices; close on the summary table. |

**Fallbacks.** The plan PR (Act 2) and the baseline stack (Act 3) are each a complete story alone.
If a session runs long, cut Act 4 and go straight to the fan-out. Never demo `terraform apply` into
a shared account.

## Key takeaways for the audience

1. The hardest part of a migration is discovering the assumptions, and half of them are in data, not
   infrastructure code.
2. A migration you cannot test is a rewrite. Building the baseline environment is the migration.
3. Some constraints are physics (6000 UDP ports, media latency) — a good agent designs within them
   instead of pattern-matching to an ALB.
4. One validated component becomes a playbook; the playbook becomes N parallel sessions.
