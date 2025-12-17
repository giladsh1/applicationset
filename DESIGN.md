# GitOps Repository Structure - Design Document

## Overview

This document describes the GitOps repository structure designed for managing Kubernetes applications and infrastructure. The structure emphasizes simplicity, role-based separation of concerns, and operational efficiency.

---

## Architecture Principles

### Design Goals

1. **Simplicity**: Easy to understand and manage repository structure
2. **Separation of Concerns**: Clear boundaries between DevOps and Developer responsibilities
3. **DRY Principle**: Single mono-chart structure eliminates template duplication
4. **Single-Tenant Clusters**: Support for customer/tenant-specific configurations
5. **Easy Promotion**: Simple version promotion between environments
6. **Chart Version Control**: Lock Helm chart versions in production for stability

### Key Features

- **Mono-Chart Architecture**: One shared Helm chart for all applications
- **Infrastructure as Code**: Dedicated chart for infrastructure objects (namespaces, buckets, etc.)
- **ApplicationSet-Driven**: Automated Application CRD generation with predefined templates
- **Hierarchical Values**: Layered configuration from environment → service → version
- **App of Apps Pattern**: Flexible system apps management for heterogeneous components

---

## Repository Structure

### Directory Quick Reference

| Directory | Purpose | Who Manages |
|-----------|---------|-------------|
| `apps/` | ApplicationSet definitions | DevOps |
| `charts/apps/` | Mono-chart templates | DevOps |
| `charts/infra/` | Infrastructure chart | DevOps |
| `system-apps/` | System app definitions | DevOps |
| `values-environments/` | Environment-wide config | DevOps |
| `values-apps/` | App-specific config | Developers |
| `values-system-apps/` | System app config | DevOps |
| `versions/` | Image version tags | Developers |

### Full Structure

```
applicationset/
├── apps/                           # ApplicationSet definitions per environment
│   ├── dev/
│   │   ├── apps/
│   │   │   └── appsList.json      # List of apps to deploy in dev
│   │   └── apps-applicationset.yaml
│   └── prod/
│       ├── apps/
│       │   └── apps-list.json
│       └── apps-applicationset.yaml
│
├── charts/                         # Helm charts
│   ├── apps/                       # Mono-chart for all applications
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       ├── configMap.yaml
│   │       ├── cronJob.yaml
│   │       ├── job.yaml
│   │       ├── scaledObject.yaml
│   │       ├── scaledJob.yaml
│   │       ├── podDisruptionBudget.yaml
│   │       └── serviceaccount.yaml
│   │
│   └── infra/                      # Infrastructure chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── namespace.yaml
│           ├── s3Buckets.yaml
│           └── prometheusRules.yaml
│
├── system-apps/                    # System-level applications
│   └── dev/
│       ├── root-system-apps.yaml  # App of Apps root
│       └── apps/
│           ├── external-dns.yaml
│           └── infra.yaml
│
├── values-apps/                    # Application-specific values
│   ├── app1/
│   │   ├── common.yaml            # Cross-environment app config
│   │   ├── dev.yaml               # Dev-specific overrides
│   │   └── prod.yaml              # Prod-specific overrides
│   ├── app2/
│   └── infra/                     # Infrastructure app values
│       ├── common.yaml
│       ├── dev.yaml
│       └── prod.yaml
│
├── values-environments/            # Environment & tenant-wide values
│   ├── dev/
│   │   └── common.yaml            # Dev environment globals
│   ├── prod/
│   │   └── common.yaml            # Prod environment globals
│   └── customer1/                 # Customer-specific values (for single-tenant)
│       └── common.yaml
│
├── values-system-apps/             # System apps values
│   ├── dev/
│   │   └── external-dns.yaml
│   └── prod/
│       └── external-dns.yaml
│
└── versions/                       # Version tags (isolated for easy promotion)
    ├── dev/
    │   ├── app1.yaml
    │   ├── app2.yaml
    │   └── app3.yaml
    └── prod/
        ├── app1.yaml
        └── app2.yaml
```

---

## ApplicationSets & Application Generation

ArgoCD ApplicationSets automate the creation of Application CRDs for all services.

**Features:**
- **Git File Generator**: Reads `appsList.json` to determine which apps to deploy
- **Templated Configuration**: Standardized Application spec for all apps
- **Automatic Value File Ordering**: Enforces hierarchical values pattern
- **Environment-Specific**: Separate ApplicationSet per environment

### Development Environment ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: dev-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/giladsh1/applicationset.git
        revision: dev
        files:
          - path: apps/dev/apps/appsList.json
        requeueAfterSeconds: 30
  template:
    metadata:
      name: "{{name}}-dev"
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: https://github.com/giladsh1/applicationset.git
        targetRevision: dev
        path: charts/apps
        helm:
          valueFiles:
            - ../../values-environments/dev/common.yaml
            - ../../values-apps/{{name}}/common.yaml
            - ../../values-apps/{{name}}/dev.yaml
            - ../../versions/dev/{{name}}.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: dev
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Application List File

```json
[
    {
        "name": "app1"
    },
    {
        "name": "app2"
    }
]
```

**Adding a New Application:**
1. Add entry to `apps/{env}/apps/appsList.json`
2. Create value files in `values-apps/{app}/`
3. Create version file in `versions/{env}/{app}.yaml`
4. Commit and push - ApplicationSet automatically creates the Application CRD

---

## Helm Values Hierarchy

Values are applied in a specific order, allowing progressive overrides from general to specific:

### Value Loading Order

```
1. values-environments/{env}/common.yaml      # Environment-wide settings
2. values-apps/{app}/common.yaml              # App settings across all environments
3. values-apps/{app}/{env}.yaml               # App + Environment specific overrides
4. versions/{env}/{app}.yaml                  # Version tag (image version)
```

### Example Configuration

**Environment Common Values** (`values-environments/dev/common.yaml`):
```yaml
env:
  name: dev

annotations:
  app.kubernetes.io/env: "{{ .Values.env.name }}"

configmap:
  enabled: true
  data:
    DB_HOST: dev-db-host
```

**Application Common Values** (`values-apps/app1/common.yaml`):
```yaml
fullnameOverride: app1

replicaCount: 1

deployment:
  enabled: true
  podDisruptionBudget:
    enabled: true

service:
  enabled: true
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: 8080

resources:
  limits:
    memory: 50Mi
  requests:
    cpu: 0.3
    memory: 50Mi

configmap:
  data:
    APP_VALUE: app1-value
```

**Environment-Specific Override** (`values-apps/app1/dev.yaml`):
```yaml
# Can override any common value for dev environment
replicaCount: 2
```

**Version Tag** (`versions/dev/app1.yaml`):
```yaml
image:
  tag: 1.29
```

### Benefits of This Hierarchy

- **Consistency**: Environment-wide settings apply to all apps
- **Flexibility**: Each app can override at multiple levels
- **Version Isolation**: Version changes don't mix with configuration
- **Clear Ownership**: Different teams can manage different layers

---

## Mono-Chart for Applications

A single, comprehensive Helm chart containing all standard Kubernetes resource templates needed by applications.

**Benefits:**
- **No Template Duplication**: All apps use the same battle-tested templates
- **Centralized Maintenance**: Bug fixes and improvements benefit all apps
- **Consistency**: Enforces organizational standards across all applications
- **Feature Toggles**: Resources are conditionally rendered based on values

---

## Version Management & Promotion

### Version File Structure

Version files contain only the image tag, keeping version information isolated:

```yaml
# versions/dev/app1.yaml
image:
  tag: 1.29
```

### Easy Promotion Between Environments

The isolated version structure enables simple promotion workflows:

```bash
# Promote all versions from dev to staging
cp -R versions/dev/* versions/staging/

# Promote single app from staging to prod
cp versions/staging/app1.yaml versions/prod/app1.yaml

# Commit promotion
git add versions/
git commit -m "Promote app1 version from staging to prod"
git push
```

### Benefits

- **Atomic Promotion**: Copy entire directory for bulk promotion
- **Selective Promotion**: Copy individual files for specific apps
- **Clear Audit Trail**: Git history shows exactly what was promoted
- **Rollback Support**: Git revert for instant rollbacks
- **No Config Mixing**: Version changes don't affect other configuration

---

## Single-Tenant Support

The structure supports single-tenant clusters where each cluster serves one customer/tenant.

### Customer-Specific Values

```yaml
# values-environments/customer1/common.yaml
env:
  name: customer1
annotations:
  app.kubernetes.io/env: "{{ .Values.env.name }}"

configmap:
  enabled: true
  data:
    DB_HOST: customer1-db-host
    TENANT_ID: 123456
```

### Tenant-Specific ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: customer1-apps
spec:
  generators:
    - git:
        repoURL: https://github.com/giladsh1/applicationset.git
        revision: customer1
        files:
          - path: apps/customer1/apps/appsList.json
  template:
    spec:
      source:
        helm:
          valueFiles:
            - ../../values-environments/customer1/common.yaml
            - ../../values-apps/{{name}}/common.yaml
            - ../../values-apps/{{name}}/customer1.yaml
            - ../../versions/customer1/{{name}}.yaml
```

### Benefits

- **Tenant Isolation**: Each tenant gets dedicated configuration
- **Shared Codebase**: All tenants use same charts and templates
- **Customization**: Per-tenant overrides without code duplication
- **Scalability**: Easy to add new tenants

---

## System Apps Management

System applications (like external-dns, ingress controllers, monitoring) use the **App of Apps** pattern.

### Why App of Apps for System Apps?

System applications differ from business applications:
- Different Helm charts (external charts, not mono-chart)
- Different configurations and value structures
- Different lifecycles and dependencies
- May come from different repositories

### Benefits

- **Flexibility**: Each system app can use different charts
- **Independence**: System apps don't follow mono-chart constraints
- **Clarity**: Clear distinction between system and business apps
- **Maintainability**: Easy to add/remove system applications

---

## Infrastructure Chart

Dedicated Helm chart for managing cluster-wide and application infrastructure resources.

**Benefits:**
- **Clear Separation**: Infrastructure vs. application concerns
- **Reusability**: Same infrastructure patterns across environments
- **Version Control**: Infrastructure changes follow GitOps workflow

---

## Migration Plan

### Overview

This section outlines the steps required to migrate from the current infrastructure repository to the new GitOps repository structure.

### Required Actions

#### 1. Create New GitOps Repository

- Create a new repository named `gitops` in GitHub
- Initialize with the directory structure as defined in this document
- Set up branch protection rules for production branches
- Configure appropriate access controls and permissions

#### 2. Update CI/CD Process

- Modify application CI/CD pipelines to update the new GitOps repository
- Implement automation to:
  - Update version files in `versions/{env}/{app}.yaml` on successful builds
  - Create pull requests for version updates
  - Commit changes in the new repository format
- Run CI/CD updates in parallel to both old and new repositories during transition period

#### 3. Migrate Helm Chart Publishing

- Copy relevant GitHub Actions from the infrastructure repository
- Adapt workflows to publish Helm charts from the new `charts/apps/` and `charts/infra/` directories
- Update chart registry configurations
- Test chart publishing pipeline in non-production environment

#### 4. Implement Promotion Process

- Copy the CI/CD promotion process from the infrastructure repository
- Adapt the promotion workflow for the new structure:
  - Update to use `cp -R versions/dev/* versions/staging/` pattern
  - Modify scripts to handle the new directory structure
  - Ensure promotion creates appropriate pull requests
  - Add validation steps for version promotions

#### 5. Cutover and Transition

- **Preparation:**
  - Verify all applications are configured in the new repository
  - Test ApplicationSets in development environment
  - Validate all Helm charts are published and accessible
  
- **Cutover Process:**
  - Deploy ApplicationSets to ArgoCD in each environment
  - Monitor ArgoCD sync status for all applications
  - Verify applications are running correctly from new repository
  
- **Cleanup:**
  - Delete previous Application CRDs managed by old repository
  - Archive or delete old infrastructure repository
  - Update documentation and runbooks
  - Communicate changes to all stakeholders

### Success Criteria

- All applications successfully deployed from new GitOps repository
- CI/CD pipelines updating new repository correctly
- Version promotion process working as expected
- No disruption to running applications during transition
- Old repository successfully deprecated

---

## Conclusion

This GitOps repository structure provides a robust, scalable foundation for managing Kubernetes applications across multiple environments and tenants. The design emphasizes:

- **Simplicity** through clear structure and conventions
- **Maintainability** via mono-chart and DRY principles
- **Flexibility** with hierarchical values and tenant support
- **Reliability** through version locking and automated processes
- **Collaboration** via role-based separation of concerns

The structure is production-ready and designed to scale with organizational growth while remaining approachable for new team members.

---

## Document Information

- **Last Updated**: December 17, 2025
- **Version**: 1.0
- **Status**: Draft for Review
- **Author**: DevOps Team
- **Reviewers**: [To be assigned]

