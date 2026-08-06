# Cloud & Infrastructure

Challenges focused on Infrastructure as Code, Kubernetes, GitOps, cloud cost optimization, and platform-conformant architecture.

> **Job titles:** Cloud Engineer, Platform Engineer, Infrastructure Engineer, Cloud Architect

## Modules

| Module | Difficulty | Time |
|--------|-----------|------|
| [IaC Translation](iac-translation.md) | Intermediate | 45 min |
| [On-Prem Platform to AWS Migration](onprem-platform-to-aws-migration.md) | Advanced | 90 min |
| [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) | Advanced | 75 min |
| [GitOps & ArgoCD Setup](gitops-argocd-setup.md) | Advanced | 75 min |
| [Kubernetes Manifest Generation](kubernetes-manifest-generation.md) | Intermediate–Advanced | 60 min |
| [Terraform Module Extraction](terraform-module-extraction.md) | Intermediate–Advanced | 60 min |
| [Cost Optimization Analysis](cost-optimization-analysis.md) | Intermediate | 45 min |

## Repositories

| Repository | Compatible Modules |
|------------|--------------------|
| ivozprovider | [On-Prem Platform to AWS Migration](onprem-platform-to-aws-migration.md) |
| hosting-client-timesheet-app | [IaC Translation](iac-translation.md), [Terraform Module Extraction](terraform-module-extraction.md), [Cost Optimization Analysis](cost-optimization-analysis.md) |
| cal.com-infra | [IaC Translation](iac-translation.md), [Cost Optimization Analysis](cost-optimization-analysis.md) |
| app_dotnet-angular-monolith | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) |
| app_dotnet-angular-microservices | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (landing repo) |
| platform-engineering-shared-services | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (context) |
| app_dotnet-angular-monolith-iac | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (context) |

## When to Use This Category

- Cloud / Platform Engineering audiences
- Workshops showing Devin's ability to generate and refactor infrastructure code
- On-Prem Platform to AWS Migration is the only module with a genuine legacy distributed estate — Debian packages configured by interactive debconf prompts, systemd, per-node BIND service discovery, a Jenkins shared-library pipeline, and real-time media that rules out the obvious container-plus-load-balancer answer. Use it when the audience owns a data centre rather than a greenfield.
- Platform-Conformant Microservice Decomposition is the most advanced challenge — combines code extraction, IaC generation, and platform conformance in a single session
- Cost Optimization Analysis is relevant for FinOps-focused audiences
- Pairs well with [DevOps & CI/CD](../devops-cicd/) for a full platform engineering workshop
- For monitoring and incident response, see [Observability & SRE](../observability-sre/)
