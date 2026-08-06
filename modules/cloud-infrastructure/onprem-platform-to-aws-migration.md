# On-Prem Platform to AWS Migration

## Repositories

- [ivozprovider](#ivozprovider)

---

## Challenge

Migrate a distributed on-premises platform to AWS end to end: analyse the existing estate, translate
host-level assumptions into managed services, containerize what should be containerized, replace a
legacy Jenkins pipeline, build a validation loop that exercises the migrated stack, and fan the
pattern out across the remaining services.

Unlike a single-app-on-a-VM migration, this platform has real-time media, four host profiles, 25
Debian packages configured by interactive debconf prompts, and node identity stored **in its own
database** — so the exercise forces genuine architecture decisions rather than "containerize it and
put an ALB in front".

## Target Outcomes

- A reviewed, docs-only migration plan with a host-assumption inventory and dependency-ordered waves
- Four prompts to get there: analyse → plan → build the feedback loop → execute
- A landing zone in Terraform (VPC, Route 53 private zone replacing per-node BIND, ECR, OIDC, secrets)
- Aurora MySQL replacing Percona, including the grants and server settings RDS will not allow as-is
- The web plane containerized on ECS/ALB with secrets, health checks, limits and rollback
- A runnable local baseline stack + the repo's 48 SIP call-flow scenarios as the acceptance gate
- GitHub Actions replacing a 780-line Jenkinsfile with a stage-by-stage coverage table
- A migration playbook and one PR per service from parallel child sessions

## What Participants Will Learn

- How Devin discovers implicit infrastructure assumptions, including ones that only exist in data
- How to make a migration testable before it is attempted, and why that is the actual unlock
- How to constrain an agent with physics (UDP port ranges, media latency) instead of patterns
- How one validated migration becomes a playbook, then N parallel child sessions

## Devin Features Exercised

- Ask Devin for read-only infrastructure analysis over a ~7.9k-file estate
- Multi-plane Terraform generation and validation
- Containerization with health checks, non-root, secrets and resource limits
- CI/CD translation (Jenkins shared-library pipeline → reusable GitHub Actions workflows)
- Test-harness construction (the highest-value step) and output comparison
- Playbooks and child-session fan-out

## Difficulty

Advanced

## Estimated Time

90 minutes (prompts 1–3 need no AWS account)

---

## <a id="ivozprovider"></a>ivozprovider

**Repository:** [ivozprovider](https://github.com/codev-workshops/ivozprovider)

Multitenant VoIP platform: Kamailio SIP proxies, Asterisk 20 application servers, rtpengine media
relays, Percona MySQL, Redis Sentinel, CGRateS billing, PHP/Symfony REST API, four React portals,
nine Go/PHP microservices. Deployed as Debian packages + systemd across four host profiles, built by
Jenkins. No Terraform, no GitHub Actions, and no way to run the telephony plane locally.

Full strategy, wave plan, acceptance gates and run of show:
[`workshops/onprem-platform-to-aws-migration/`](../../workshops/onprem-platform-to-aws-migration/README.md).
Complete prompt set (four prompts — analyse, plan, feedback loop, execute — then two to scale):
[`prompts.md`](../../workshops/onprem-platform-to-aws-migration/prompts.md).

### Starting-state findings (verified)

| # | Finding | Why it matters |
|---|---|---|
| 1 | Node identity lives in `ApplicationServers`, `ProxyUsers`, `ProxyTrunks`, `kam_dispatcher`, `kam_rtpengine` rows, rendered into `listeners.cfg` by a Perl script (`profiles/proxy/etc/kamailio/autoconf`) | The platform cannot autoscale without stable addresses or a new node registrar — the migration's defining decision |
| 2 | 12 more address columns describe **carrier and customer** endpoints (`CarrierServers.ip`, `kam_trusted.src_ip`, `Friends.ip`, `Companies.ipFilter`, …) | Changing public IPs breaks third-party ACLs; it is a commercial exercise, not just Terraform |
| 3 | Service discovery is a per-node BIND zone rewritten by `sed` in a postinst | → Route 53 private hosted zone |
| 4 | 30 debconf templates supply configuration interactively at install time | → SSM/Secrets Manager; each prompt needs a declared cloud equivalent |
| 5 | `GRANT ALL ON *.*` + `mysql_native_password` + `sed`-ing `/etc/mysql/conf.d` | RDS forbids all three as written |
| 6 | `chmod 777 /opt/irontec/ivozprovider/storage` holds recordings, voicemail, invoices and **JWT private keys** | → S3 + EFS access point + Secrets Manager |
| 7 | rtpengine binds one public IP over UDP 13000–19000 | Rules out a load balancer for media; EIP per node |
| 8 | `docker-compose.yml` contains no Kamailio, Asterisk or rtpengine | The platform cannot be run, so nothing can be compared before/after |
| 9 | 48 unused black-box SIP scenario files in `tests/bbs/` emitting JUnit XML | The migration's ready-made acceptance gate |
| 10 | 780-line Jenkinsfile on a shared library, with a homemade content-hash test cache in `JENKINS_HOME` | Cannot be lifted to ephemeral runners without redesign |

### Step 1: Paste into Devin

> Produce an AWS migration plan for IvozProvider as a docs-only PR. Read debian/ (control,
> \*.postinst, \*.templates, systemd units), profiles/, kamailio/, asterisk/config/, microservices/,
> docker-compose.yml, Jenkinsfile and tests/. Include: a current-state diagram with every port and
> protocol, signalling and media separated; a host-assumption inventory mapping each assumption to an
> AWS equivalent with the code or config change and risk; a plane-by-plane target design that
> evaluates NLB vs EIP-per-node against rtpengine's 13000-19000 UDP range and states a decision; the
> autoscaling problem stated explicitly, given that node identity lives in ApplicationServers,
> ProxyUsers, ProxyTrunks, kam_dispatcher and kam_rtpengine rows written by
> profiles/proxy/etc/kamailio/autoconf; waves in dependency order with entry criteria, exit criteria
> and rollback; and what must not move in wave 1. No code changes. Put anything you could not
> determine in an "Open questions" section instead of assuming it.

That is prompt 2. Prompt 1 (Analyse) comes before it and runs as Ask Devin with no environment;
prompt 3 builds the feedback loop and is the one that changes the demo from plausible to provable;
prompt 4 executes the first three waves. See
[`prompts.md`](../../workshops/onprem-platform-to-aws-migration/prompts.md).

### Step 2: Research with Ask Devin

- *"Which values are supplied by debconf prompts at install time, and which file is each one sed-ed into?"*
- *"Every table and column holding an IP, port, SIP URI or hostname — which describe our infrastructure and which describe a customer or carrier endpoint?"*
- *"What does the Jenkinsfile do that a naive GitHub Actions port would silently lose?"*
- *"Which host-level assumptions would break if this ran on ECS Fargate with no persistent local disk?"*

### Step 3 (Optional): Read the DeepWiki

Use DeepWiki to follow a call end to end — Kamailio users proxy → dispatcher → Asterisk → FastAGI
PHP → CGRateS — before deciding which planes may be containerized.

### Step 4 (Optional): Review & Give Feedback

- **Review the plan PR** — is every debconf prompt accounted for? Is the media decision justified by the port range rather than by habit?
- **Leave a comment** asking Devin to add the IP-continuity plan: which addresses must be preserved versus renegotiated with carriers, per brand.
- **Watch Devin respond** and push a follow-up commit.
