# Cloud & Infrastructure

Challenges focused on Infrastructure as Code, Kubernetes, GitOps, cloud cost optimization, and platform-conformant architecture.

> **Job titles:** Cloud Engineer, Platform Engineer, Infrastructure Engineer, Cloud Architect

## Modules

| Module | Difficulty | Time |
|--------|-----------|------|
| [IaC Translation](iac-translation.md) | Intermediate | 45 min |
| [VM to Cloud-Native Migration](vm-to-cloud-native-migration.md) | Advanced | 75 min |
| [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) | Advanced | 75 min |
| [GitOps & ArgoCD Setup](gitops-argocd-setup.md) | Advanced | 75 min |
| [Kubernetes Manifest Generation](kubernetes-manifest-generation.md) | Intermediate–Advanced | 60 min |
| [Terraform Module Extraction](terraform-module-extraction.md) | Intermediate–Advanced | 60 min |
| [Cost Optimization Analysis](cost-optimization-analysis.md) | Intermediate | 45 min |

## Repositories

| Repository | Compatible Modules |
|------------|--------------------|
| hosting-client-timesheet-app | [VM to Cloud-Native Migration](vm-to-cloud-native-migration.md), [IaC Translation](iac-translation.md), [Terraform Module Extraction](terraform-module-extraction.md), [Cost Optimization Analysis](cost-optimization-analysis.md) |
| app_timesheet | [VM to Cloud-Native Migration](vm-to-cloud-native-migration.md) (application) |
| cal.com-infra | [IaC Translation](iac-translation.md), [Cost Optimization Analysis](cost-optimization-analysis.md) |
| app_dotnet-angular-monolith | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) |
| app_dotnet-angular-microservices | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (landing repo) |
| platform-engineering-shared-services | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (context) |
| app_dotnet-angular-monolith-iac | [Platform-Conformant Microservice Decomposition](platform-conformant-microservice-decomposition.md) (context) |

## When to Use This Category

- Cloud / Platform Engineering audiences
- Workshops showing Devin's ability to generate and refactor infrastructure code
- VM to Cloud-Native Migration is the only module with a genuine legacy *before* state — a single EC2 instance, a hand-written deploy script, and two container defects the test suite cannot catch. Use it when the audience cares about migration risk rather than greenfield architecture.
- Platform-Conformant Microservice Decomposition is the most advanced challenge — combines code extraction, IaC generation, and platform conformance in a single session
- Cost Optimization Analysis is relevant for FinOps-focused audiences
- Pairs well with [DevOps & CI/CD](../devops-cicd/) for a full platform engineering workshop
- For monitoring and incident response, see [Observability & SRE](../observability-sre/)
