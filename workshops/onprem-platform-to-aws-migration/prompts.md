# Prompt set — on-prem VoIP platform to AWS (`ivozprovider`)

Four prompts get you from an unknown estate to a migrated, tested web/data plane. Two more scale it.
Copy-paste ready.

| # | Prompt | Deck stage | Output | AWS needed |
|---|---|---|---|---|
| 1 | [Analyse](#1-analyse) | Analyse & Plan | dependency + hazard report | no |
| 2 | [Plan](#2-plan) | Analyse & Plan | docs-only PR humans approve | no |
| 3 | [Build the feedback loop](#3-build-the-feedback-loop) | Build the Feedback Loop | runnable baseline stack + call-flow gate | no |
| 4 | [Execute waves 0–2](#4-execute-waves-02) | Migrate One Service | Terraform + Aurora + ECS, gates green | yes (sandbox) |
| 5 | [Playbook](#5-playbook) | Create a Playbook | reusable procedure | — |
| 6 | [Fan out](#6-fan-out-wave-3) | Iterate / Parallelise | one PR per microservice | yes (sandbox) |

Then the [hard waves](#hard-waves--only-once-the-feedback-loop-is-green): Asterisk, Kamailio +
rtpengine, and the Jenkins → GitHub Actions migration.

The constraints inside each prompt are the point. Drop them and the agent produces plausible-looking
but wrong infrastructure — every one of them corresponds to something in this repo that a generic
"containerize it and add a load balancer" answer gets wrong.

---

## 1. Analyse

*Read-only. Works as Ask Devin or a session. No environment, no credentials.*

```
Map how IvozProvider is deployed today and where a cloud migration will hurt. Use only the repo:
debian/ (control, *.install, *.postinst, *.templates, systemd units), profiles/, kamailio/,
asterisk/config/, microservices/, docker-compose.yml, Jenkinsfile, schema/, tests/.

Produce, each as a table with file:line evidence:
1. Host profiles: what runs on each, which packages install it, which ports and protocols it opens,
   signalling separated from media.
2. Configuration surface: every value supplied by a debconf prompt at install time, and the file it
   is sed-ed into.
3. Host-level assumptions that will not exist in AWS: the local BIND zone and everything that
   resolves through it, every filesystem path outside the app directory that is read or written,
   world-writable shared state, plaintext credentials, MySQL settings applied by editing
   /etc/mysql/conf.d, and the GRANT statements the installer runs.
4. Topology stored in the database: every table and column holding an IP, port, SIP URI or hostname.
   For each, which component consumes it, whether it describes OUR infrastructure or a
   CUSTOMER/CARRIER endpoint, and what breaks if it changes. Call out addresses a third party
   trusts, which we therefore cannot change unilaterally.
5. External dependencies, including apt repositories.
6. What can be tested today versus what cannot be run at all locally.

Do not propose a target architecture. Where the repo does not tell you, say so instead of assuming.
```

Expect it to surface: node identity living in `ApplicationServers` / `ProxyUsers` / `ProxyTrunks` /
`kam_dispatcher` / `kam_rtpengine` rows rendered into `listeners.cfg` by
`profiles/proxy/etc/kamailio/autoconf`; carrier- and customer-trusted addresses; and that the
telephony plane has no local environment.

---

## 2. Plan

*Docs-only PR — the artifact humans review before anything is built.*

```
Turn that analysis into an AWS migration plan, as a docs-only PR. No code changes.

Include:
1. Current-state diagram (mermaid) with every port, protocol and data flow, signalling and media
   separated.
2. Assumption -> AWS equivalent -> code/config change -> risk, one row per host assumption from the
   analysis. Every debconf prompt must appear with a declared cloud equivalent. Flag explicitly the
   things RDS will not allow as written: GRANT ALL ON *.*, mysql_native_password, and settings
   applied by editing /etc/mysql/conf.d.
3. Target design per plane: data, cache, storage, web/API, workers, Asterisk, Kamailio, rtpengine,
   CI/CD, observability. For media, evaluate NLB vs one Elastic IP per node against rtpengine's
   13000-19000 UDP range and state a decision with the reason. Do not put SIP or RTP behind an ALB.
4. The autoscaling problem: node identity is database rows written by
   profiles/proxy/etc/kamailio/autoconf. Give two options - stable per-node addresses, or a
   registrar that maintains those rows from instance/task lifecycle events - with trade-offs.
5. Waves in dependency order, each with entry criteria, exit criteria, validation gates and
   rollback. State what must NOT move in wave 1.
6. IP continuity: which public addresses must be preserved (BYOIP / EIP reuse) versus renegotiated
   with carriers and tenants, per brand.
7. Acceptance gates every migrated component must pass, with the exact commands.
8. Open questions for the platform team - anything needing a human decision (which IPs move,
   schema changes to billing tables, recording/CDR data residency, emergency-call routing, cutover
   windows) goes here rather than being decided by you.
```

---

## 3. Build the feedback loop

*Do this before migrating anything risky. It is the highest-value prompt in the set.*

```
This platform cannot be run locally - docker-compose.yml has no Kamailio, no Asterisk and no
rtpengine - so today there is no way to prove a migration preserves behaviour. Build that
environment first.

1. Extend docker-compose.yml into a legacy baseline stack: the existing data/redis/backend/portal
   services plus kamailio-users, kamailio-trunks, asterisk and rtpengine, installed from
   packages.irontec.com and configured the way the packages configure them - generate
   listeners.cfg and ports.cfg the way profiles/proxy/etc/kamailio/autoconf does.
2. Seed the database: schema/initial.sql, all Doctrine migrations, then the fixtures the call tests
   assume (tests/bbs/environment.yaml users, the residential and retail brands, DDIs, IVRs, queues).
3. Make tests/bbs runnable: a script that builds bbs (github.com/irontec/bbs), runs every scenario
   file via tests/bbs/entrypoint.sh, and writes one JUnit XML summary.
4. Add comparison, so any migrated stack can be judged against this baseline: extract the resulting
   CDRs (kam_users_cdrs, kam_trunks_cdrs, BillableCalls) into a normalised CSV, and a
   compare-cdrs script that diffs two runs on call count and per-call duration and billing fields.
5. Wire the existing suites into one entrypoint too: library/bin/test-* (phpspec, phpstan, psalm,
   codestyle), the portal lint/i18n/build scripts, tests/rest/postman-api-tests.json via newman.

Done when, on a machine with only Docker: `./scripts/legacy-baseline up` brings the platform up and
`./scripts/call-tests` prints a pass/fail count per scenario. Record that pass count as the
baseline. Anything you cannot make pass, mark as known-failing with the reason - never delete or
weaken a scenario to get a green run.
```

---

## 4. Execute waves 0–2

*Foundations, data plane, web plane. One PR per wave, each with its gate output pasted in.*

```
Migrate the web and data planes to AWS, following the plan. Three PRs, in this order, each with
terraform plan output and gate results in the description, and rollback steps stated.

PR1 - foundations. terraform/aws with remote state (S3 + DynamoDB lock), one module per concern:
VPC with public/private subnets across 3 AZs + NAT; Route 53 private hosted zone
ivozprovider.local reproducing today's BIND records (data, cache, storage, logs, jobs, users,
trunks, hep) as Cloud Map / ALB aliases; ECR; Secrets Manager entries for the MySQL users and the
JWT keypair; a GitHub Actions OIDC role scoped to these resources; CloudWatch log groups.
Parameterised per environment, no credentials in the repo. Explain how each Route 53 record replaces
profiles/data/etc/bind/.

PR2 - data plane. Aurora MySQL 8.0 (writer + reader, encrypted, private subnets) with a parameter
group reproducing every setting currently applied by editing /etc/mysql/conf.d
(default-time-zone=utc, character-set-server, skip-character-set-client-handshake,
wait_timeout=604800, and the auth plugin Asterisk's ODBC driver and Kamailio need); document
anything RDS cannot honour. Replace the installer's GRANT ALL ON *.* for root/kamailio/asterisk
with least-privilege users in Secrets Manager, deriving the privileges each component actually needs
from the Kamailio modparams and asterisk/config/extconfig.conf. An idempotent bootstrap job that
loads schema/initial.sql then runs all Doctrine migrations. ElastiCache Redis replacing Sentinel,
plus the client change from mymaster:26379 to the primary endpoint. A cutover runbook:
Percona -> Aurora by replication, with pt-table-checksum verification over all tables.

PR3 - web plane. Containerize the REST API and the four portals onto ECS Fargate: multi-stage images
built from the repo (no forked copies of application files), non-root, real /health endpoint and
HEALTHCHECK, CPU/memory limits, config from SSM/Secrets Manager, logs to CloudWatch, rolling deploy
with deployment circuit breaker and automatic rollback, least-privilege task role. Move the JWT
keypair out of the shared storage directory into Secrets Manager and recordings/locutions/invoices
to S3 behind a filesystem abstraction; state what still needs EFS and why - do not recreate a
world-writable share. ALB with HTTPS and per-portal routing; React bundles to S3 + CloudFront.

Gates, run and pasted per PR: terraform validate + plan clean with no replacement of stateful
resources; cold-start health check passes in an empty environment; no plaintext credential in any
config file or image layer; non-root process and no world-writable path; the REST API suite green
against the deployed API; pt-table-checksum zero diffs for migrated tables; logs reaching
CloudWatch. Stop and ask instead of proceeding if a step would change an address a carrier or
customer trusts, or requires a schema change.
```

---

## 5. Playbook

```
Turn PR3 into a reusable playbook for migrating one IvozProvider component to AWS:
(1) inputs - component, systemd unit(s), package(s), host profile, datastores, ports, whether it
    terminates SIP or media;
(2) analysis questions to answer before writing code, including which debconf values configure it
    and which database rows describe its identity;
(3) target-pattern decision tree - stateless HTTP -> Fargate behind ALB; scheduled ->
    EventBridge Scheduler; SIP signalling -> instance with a stable EIP and advertise; media ->
    EIP, never a load balancer;
(4) mandatory changes - no plaintext secrets, non-root, health check, resource limits, CloudWatch
    logs, least-privilege role, no world-writable paths;
(5) the acceptance gates with exact commands, including the call-flow and CDR comparison from the
    baseline stack;
(6) PR structure - one per component, plan output and gate results in the description, rollback
    steps;
(7) escalate-to-human triggers - any change to an address a third party trusts, any schema change,
    any in-call behaviour change.
Save it as a Devin playbook and commit the markdown under docs/migration/.
```

---

## 6. Fan out (wave 3)

```
Start one child session per remaining microservice: balances, click2call, provision, realtime,
recordings, router, webhooks, workers, plus the scheduler units (ivozprovider-scheduler,
ivozprovider-cdrs, ivozprovider-scheduler-historic-calls). Each session follows
docs/migration/playbook.md, reads its own systemd unit and postinst for the configuration it needs,
produces a terraform module plus an ECS service or EventBridge schedule, runs the gates, and opens
one PR with the gate output and terraform plan in the description.
Where the playbook is wrong or missing a step - for the scheduled jobs: overlapping runs, the
platform's UTC assumption, idempotency, at-least-once delivery, dead-lettering - fix the playbook in
the same PR and say what changed. Any session must stop and report instead of guessing if its
component listens on a SIP or RTP port, its identity is a row in
ApplicationServers/ProxyUsers/ProxyTrunks/kam_dispatcher/kam_rtpengine, or it needs a schema change.
Give me a summary table: session, component, target pattern, PR, gate result, playbook gaps.
```

---

## Hard waves — only once the feedback loop is green

### Asterisk application servers (wave 4)

```
Containerize the Asterisk application server and run it on ECS with awsvpc networking. It reads its
configuration from MySQL through ODBC realtime (asterisk/config/extconfig.conf, res_odbc.conf) and
calls PHP over FastAGI (debian/systemd/fastagi@.service, asterisk/agi/). Requirements: ODBC
credentials from Secrets Manager instead of sed-ed into /etc/odbc.ini; FastAGI reachable without the
debconf-supplied fastagi_server_address; the AS registers itself in ApplicationServers and
kam_dispatcher on start and deregisters on stop (or, if you choose static addressing, justify it);
voicemail spool on EFS with an access point, or explain how you moved it to S3; graceful shutdown
that drains active calls before the task stops.
Gates: cold-start health, no plaintext secrets, non-root, the bbs suite passing against this image
via the baseline stack, CDRs matching the baseline run, registration surviving node replacement, and
a rolling deploy with no in-call drop or a documented drain.
```

### Kamailio + rtpengine (wave 5)

```
Migrate the proxy profile to AWS. Constraints to respect rather than design around: rtpengine binds
one public IP over UDP 13000-19000; Kamailio needs stable listen and advertise addresses; DMQ
replicates state between proxies; usrloc, dispatcher, permissions and acc live in the database; and
carrier ACLs and customer devices trust the current public IPs (kam_trusted.src_ip,
CarrierServers.ip, DDIProviderAddresses.ip, Friends.ip, ResidentialDevices.ip, RetailAccounts.ip,
Companies.ipFilter).
Deliver: Terraform for proxy and media nodes with one EIP each, security groups scoped per protocol,
an ASG or fixed instances with a documented reason, cloud-init that replaces the autoconf Perl
script by generating listeners.cfg/ports.cfg from the database at boot, DMQ peer discovery that
survives node replacement, and a node registrar keeping ProxyUsers, ProxyTrunks, kam_dispatcher and
kam_rtpengine consistent with reality. Plus the per-brand IP-continuity plan: which addresses are
preserved versus renegotiated.
Gates: the bbs suite, CDR match, registration surviving node replacement, media flowing both ways
after failover with MOS fields populated, and a documented failover test - kill a proxy node and
prove registrations and in-progress calls behave as designed.
```

### CI/CD migration (wave 6)

```
Replace the Jenkinsfile with GitHub Actions without losing capability. Map every stage: the
testing-base image build, the Generic stage (test-commit-tags, test-file-perms, composer deps), the
backend suites via library/bin/test-*, schema tests against Percona 8.0, the four portal
lint/i18n/build jobs, the Cypress/Pact jobs against the httpd image, dpkg-buildpackage -b, the
StackHawk DAST scan, and the functional-review and mergeability gates.
Requirements: reusable workflows instead of the shared library; actions/cache plus path filters
replacing the hand-rolled cached_pipelines.txt hash cache (MAX_HASHES=400) - explain the mapping;
label and commit-tag conditionals preserved (ci-force-tests, hasCommitTag("core:")); OIDC to AWS, no
static keys; ECR pushes; Jira and Mattermost notifications preserved or explicitly dropped with
sign-off; terraform validate/plan and image scanning added as required checks; ephemeral runners only
- nothing may depend on reuseNode or JENKINS_HOME.
Produce a coverage table: Jenkins stage -> Actions job -> status (migrated / redesigned / dropped
with reason). Nothing may be silently missing.
```
