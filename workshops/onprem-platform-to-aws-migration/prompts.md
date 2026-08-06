# Prompt set — on-prem VoIP platform to AWS (`ivozprovider`)

Copy-paste ready. Ordered to match the six stages of the *Infra & Platform Migrations* deck:
analyse → migrate one → feedback loop → playbook → generalise → parallelise.

Every prompt states **scope, evidence to read, constraints, and the gate it must satisfy**. Prompts
that omit the constraints are the reason migration sessions produce plausible-looking but wrong
infrastructure.

---

## Stage 1 — Analyse & Plan

### 1a. Ask Devin — dependency map (read-only, no environment needed)

```
Map how IvozProvider is deployed today, using only what is in the repo. Cover:
(1) every host profile in profiles/ and which packages in debian/control install onto it;
(2) every systemd unit and what it runs;
(3) every value that is supplied by a debconf prompt at install time, and which file it is
    sed-ed into;
(4) every hostname the code resolves through the local BIND zone, and what depends on it;
(5) every filesystem path outside the application directory that is read or written at runtime;
(6) every external network dependency, including apt repositories.
Output one table per item with file:line evidence. Do not propose a target architecture yet.
```

### 1b. Ask Devin — the infrastructure hidden in the database

```
The platform stores its own topology in MySQL. Using schema/initial.sql, schema/DoctrineMigrations
and the code that reads them, list every table and column that holds an IP address, port, SIP URI
or hostname. For each one, say which component consumes it, whether it describes OUR
infrastructure or a CUSTOMER/CARRIER endpoint, and what breaks if the value changes. Call out
anything that a cloud migration cannot change unilaterally because a third party trusts that
address.
```

### 1c. Session — the migration plan (docs-only PR; the artifact humans review)

```
Produce an AWS migration plan for IvozProvider as a docs-only PR. Read the Terraform-free reality
first: debian/ (control, *.postinst, *.templates, systemd units), profiles/, kamailio/,
asterisk/config/, microservices/, docker-compose.yml, Jenkinsfile, tests/.

The plan must contain:
1. A current-state architecture diagram (mermaid) with every port, protocol and data flow,
   signalling and media separated.
2. A host-assumption inventory: assumption -> AWS equivalent -> what has to change in code or
   config -> risk. Include the debconf configuration surface, the BIND service directory, the
   chmod 777 shared storage, the ODBC plaintext credentials, and the GRANT ALL /
   mysql_native_password requirements that RDS will not allow.
3. A plane-by-plane target design (data, cache, storage, web/API, workers, Asterisk, Kamailio,
   rtpengine, CI/CD, observability). For the media plane, evaluate NLB vs EIP-per-node against
   rtpengine's 13000-19000 UDP range and state a decision with the reason.
4. The autoscaling problem stated explicitly: node identity currently lives in ApplicationServers,
   ProxyUsers, ProxyTrunks, kam_dispatcher and kam_rtpengine rows written by
   profiles/proxy/etc/kamailio/autoconf. Give two options - stable addresses, or a registrar that
   maintains those rows from ECS/ASG lifecycle events - with trade-offs.
5. Waves in dependency order, each with entry criteria, exit criteria and rollback.
6. What must NOT move in wave 1, and why.

No code changes in this PR. Anything you could not determine from the repo goes in an
"Open questions for the platform team" section rather than being assumed.
```

---

## Stage 2 — Migrate one service end-to-end (the web plane)

### 2a. Foundations

```
Create a terraform/aws stack (remote state in S3 + DynamoDB lock, one module per concern) for the
IvozProvider landing zone: VPC with public/private subnets across 3 AZs + NAT, Route 53 private
hosted zone ivozprovider.local reproducing today's records (data, cache, storage, logs, jobs, users,
trunks, hep) as Cloud Map / ALB aliases, ECR repositories, Secrets Manager entries for the MySQL
users and the JWT keypair, an OIDC role for GitHub Actions scoped to these resources, and
CloudWatch log groups. No credentials in the repo; everything parameterised per environment
(dev/staging/prod). terraform validate and plan must pass with no AWS calls beyond read-only.
Explain in the PR how each Route 53 record replaces the BIND zone in profiles/data/etc/bind/.
```

### 2b. Data plane

```
Move the data profile to Aurora MySQL 8.0. Requirements:
- Aurora cluster (writer + 1 reader), encrypted, in private subnets, with a parameter group that
  reproduces every setting currently applied by editing /etc/mysql/conf.d: default-time-zone=utc,
  character-set-server, skip-character-set-client-handshake, wait_timeout=604800 and the
  authentication plugin Asterisk's ODBC driver and Kamailio need. Document any setting that RDS
  cannot honour.
- Replace ivozprovider-profile-data.postinst's GRANT ALL ON *.* for root/kamailio/asterisk with
  least-privilege users per component, in Secrets Manager, and state exactly which privileges each
  component actually needs (derive it from the Kamailio modparams and
  asterisk/config/extconfig.conf, not from guesswork).
- A repeatable bootstrap job that loads schema/initial.sql then runs all 124 Doctrine migrations,
  idempotently.
- ElastiCache Redis replacing the Sentinel setup, plus the client-side change from sentinel
  (mymaster:26379) to the primary endpoint.
- A cutover runbook: Percona -> Aurora with replication, plus a pt-table-checksum verification step
  covering all 155 tables.
Gate: terraform plan clean, bootstrap job green against a throwaway cluster or a local
MySQL-compatible container, pt-table-checksum script committed and runnable.
```

### 2c. Containerize and deploy the web plane

```
Containerize the REST API and the four portals and deploy them on ECS Fargate.
- Multi-stage images built from the repo (no forked copies of application files anywhere), running
  as a non-root user, with a real /health endpoint and a HEALTHCHECK.
- Move the JWT keypair out of /opt/irontec/ivozprovider/storage/jwt into Secrets Manager, and
  recordings/locutions/invoices to S3 behind a filesystem abstraction; document what still needs
  EFS and why.
- ALB with HTTPS, per-portal target groups and path routing; React bundles to S3+CloudFront.
- Task definitions with CPU/memory limits, env from SSM/Secrets Manager, logs to CloudWatch,
  rolling deploy with deployment circuit breaker and automatic rollback.
- Task role with least privilege for S3, Secrets Manager and CloudWatch only.
Gates: G1-G4 and G11 from the acceptance list, plus tests/rest/postman-api-tests.json passing
against the deployed API. Paste the gate output in the PR.
```

---

## Stage 3 — Build the feedback loop (before the hard waves)

```
There is no way to run this platform's telephony plane locally, so there is no way to prove a
migration preserves behaviour. Build that environment.

Extend docker-compose.yml into a full local baseline stack: the existing data/redis/backend/portal
services plus kamailio-users, kamailio-trunks, asterisk and rtpengine, installed from
packages.irontec.com, configured the way the packages configure them (generate listeners.cfg and
ports.cfg the way profiles/proxy/etc/kamailio/autoconf does), with the DB seeded from
schema/initial.sql + all migrations + the fixtures the bbs tests assume (tests/bbs/environment.yaml
users alice/bob/charlie/dave/eve/friend, the residential and retail brands, DDIs, IVRs, queues).

Then make tests/bbs runnable against it: a script that builds bbs (github.com/irontec/bbs), runs
every scenario file via tests/bbs/entrypoint.sh, and writes a single JUnit XML summary. Add a
second script that extracts the resulting CDRs (kam_users_cdrs, kam_trunks_cdrs, BillableCalls)
into a normalised CSV for comparison between two stacks.

Definition of done: `./scripts/legacy-baseline up` then `./scripts/call-tests` prints a pass/fail
count for every scenario on a machine with only Docker installed, and `./scripts/compare-cdrs
legacy.csv aws.csv` reports differences. Anything you cannot make pass, mark as a known-failing
baseline with the reason - do not delete or weaken a scenario.
```

---

## Stage 4 — Create the playbook

```
Turn the wave-2 migration into a reusable playbook for migrating one IvozProvider component to AWS.
Structure it as:
(1) inputs the session needs - component name, systemd unit(s), package(s), host profile,
    datastores touched, ports, whether it terminates SIP or media;
(2) the analysis questions that must be answered before writing code, including "which debconf
    values configure it" and "which DB rows describe its identity";
(3) the target-pattern decision tree - stateless HTTP -> Fargate behind ALB; scheduled ->
    EventBridge Scheduler; SIP signalling -> instance with EIP and advertise; media -> EIP, never
    a load balancer;
(4) the mandatory changes - no plaintext secrets, non-root, health check, resource limits, logs to
    CloudWatch, least-privilege task role, no world-writable paths;
(5) the acceptance gates G1-G12 with the exact commands;
(6) PR structure - one PR per component, terraform plan output and gate results in the
    description, rollback steps stated;
(7) escalate-to-human triggers - anything that changes a public IP a carrier or customer trusts,
    any schema change, any in-call behaviour change.
Save it as a Devin playbook and include the markdown in the repo under docs/migration/.
```

---

## Stage 5 — Iterate & generalise

```
Apply the playbook to ivozprovider-scheduler, ivozprovider-cdrs and
ivozprovider-scheduler-historic-calls (debian/systemd/*.service). These are cron-shaped workloads.
Where the playbook is wrong, ambiguous or missing a step for scheduled jobs - overlapping runs,
timezone (the platform assumes UTC everywhere), idempotency, at-least-once delivery, dead-letter
handling - fix the playbook in the same PR and say what you changed and why.
```

---

## Stage 6 — Parallelise with child sessions

```
Start one child session per remaining microservice: balances, click2call, provision, realtime,
recordings, router, webhooks, workers, plus the async-workers and webhooks systemd units. Each
session must: follow the migration playbook; read its own systemd unit and postinst for the
configuration it needs; produce a terraform module and an ECS service (or EventBridge schedule);
run gates G1-G4 and G11; open one PR with the gate output and terraform plan in the description;
and stop and report instead of guessing if it touches SIP signalling, media, or any address a
third party trusts. Give me a summary table of session, component, target pattern, PR, gate result.
```

### Child-session template (one per component)

```
Migrate <COMPONENT> to AWS following docs/migration/playbook.md.
Inputs: systemd unit debian/systemd/<unit>.service, package debian/<pkg>.install +
<pkg>.postinst, source microservices/<dir>/.
Do exactly what the playbook says, in its order. Run every gate it lists and paste the output in
the PR. If the playbook is missing something this component needs, note it in the PR under
"Playbook gaps" - do not improvise silently.
Escalate instead of proceeding if: the component listens on a SIP or RTP port, its identity is a
row in ApplicationServers/ProxyUsers/ProxyTrunks/kam_dispatcher/kam_rtpengine, or it needs a
schema change.
```

---

## The hard waves — only after the feedback loop is green

### Asterisk application servers (wave 4)

```
Containerize the Asterisk application server and run it on ECS with awsvpc networking. It reads its
configuration from MySQL through ODBC realtime (asterisk/config/extconfig.conf, res_odbc.conf) and
calls PHP over FastAGI (debian/systemd/fastagi@.service, asterisk/agi/). Requirements: ODBC
credentials from Secrets Manager instead of sed-ed into /etc/odbc.ini; FastAGI reachable without
the debconf-supplied fastagi_server_address; the AS registers itself in ApplicationServers and
kam_dispatcher on start and deregisters on stop (or, if you choose static addressing, justify it);
voicemail spool on EFS with an access point, or explain how you moved it to S3; graceful shutdown
that drains active calls before the task stops.
Gates: G2, G3, G4, G5 (the bbs suite via the local stack with this image), G6, G8, G10.
```

### Kamailio + rtpengine (wave 5)

```
Migrate the proxy profile to AWS. Constraints you must respect rather than design around:
rtpengine binds one public IP with UDP 13000-19000; Kamailio needs stable listen and advertise
addresses; DMQ replicates state between proxies; usrloc, dispatcher, permissions and acc are in the
database; carrier ACLs and customer devices trust the current public IPs (kam_trusted.src_ip,
CarrierServers.ip, DDIProviderAddresses.ip, Friends.ip, ResidentialDevices.ip, RetailAccounts.ip,
Companies.ipFilter).
Deliver: Terraform for proxy and media nodes with one EIP each, security groups scoped per
protocol, an ASG or fixed instances with a documented reason, cloud-init that replaces the
autoconf Perl script by generating listeners.cfg/ports.cfg from the database at boot, DMQ peer
discovery that survives node replacement, and a node registrar that keeps ProxyUsers, ProxyTrunks,
kam_dispatcher and kam_rtpengine consistent with reality.
Also deliver an IP-continuity plan: which addresses must be preserved (BYOIP or EIP reuse) versus
renegotiated with carriers and tenants, per brand.
Gates: G1, G5, G6, G8, G9, G10, plus a documented failover test - kill a proxy node, prove
registrations and in-progress calls behave as designed.
```

### CI/CD migration (wave 6)

```
Replace the Jenkinsfile with GitHub Actions without losing capability. Map every stage: the
testing-base image build, the Generic stage (test-commit-tags, test-file-perms, composer deps),
the backend suites via library/bin/test-*, schema tests against Percona 8.0, the four portal
lint/i18n/build jobs, the Cypress/Pact jobs against the httpd image, dpkg-buildpackage -b, the
StackHawk DAST scan, and the functional-review and mergeability gates.
Requirements: reusable workflows instead of the shared library; actions/cache plus path filters
replacing the hand-rolled cached_pipelines.txt hash cache (MAX_HASHES=400) - explain the mapping;
label and commit-tag conditionals preserved (ci-force-tests, hasCommitTag("core:")); OIDC to AWS,
no static keys; ECR pushes; Jira and Mattermost notifications preserved or explicitly dropped with
sign-off; terraform validate/plan and container image scanning added as required checks; ephemeral
runners only - nothing may depend on reuseNode or JENKINS_HOME.
Produce a coverage table: Jenkins stage -> Actions job -> status (migrated / redesigned / dropped
with reason). Nothing may be silently missing.
```
