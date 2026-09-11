# GitOps-Driven Kubernetes Platform

A production-style Kubernetes platform demonstrating **GitOps, CI/CD, Helm, observability, security scanning, alerting, and Kubernetes self-healing** using a containerized Neon Runner application.

The project separates application development from infrastructure and deployment, following a GitOps workflow where **Git is the source of truth**.

---

## 🚀 Project Overview

This project demonstrates an end-to-end DevOps workflow:

```text
Developer
   │
   ▼
GitHub
   │
   ├── GitHub Actions
   │      ├── Tests
   │      ├── Build
   │      ├── Docker Images
   │      └── Trivy Security Scan
   │
   ▼
Docker Hub
   │
   ▼
Git Repository
   │
   ▼
Argo CD
   │
   ▼
Kubernetes
   │
   ├── Neon Runner Frontend
   └── Neon Runner Backend
          │
          ▼
   Prometheus
          │
          ▼
       Grafana
          │
          ▼
       Discord