# OpenRaptor Cyber Range — OpenRaptor

> A modular, Azure-hosted cyber range for CIRT analyst training in threat detection, log analysis, and incident response.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Azure](https://img.shields.io/badge/Platform-Microsoft%20Azure-blue)](https://azure.microsoft.com)
[![IaC: Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4)](https://www.terraform.io)

---

## Overview

OpenRaptor is a modular Azure-based cyber range designed for CIRT (Cyber Incident Response Team) analyst training. It provides realistic, narrative-driven attack scenarios with telemetry flowing into Azure Log Analytics — so analysts can practice detection and investigation using the same tools they use in production.

The design principle is **plug-and-play**: a permanent base infrastructure (domain controller, logging, network) plus disposable scenario modules that can be deployed, used, and destroyed independently. Resetting the lab for a new student takes approximately five minutes.

---

## Features

- **Modular by design** — deploy and destroy individual scenario modules without touching base infrastructure
- **Private-only VMs** — all workloads are accessed via Azure Bastion; no public IP addresses on lab VMs
- **Dual-plane telemetry** — Windows event logs, IIS logs, and Entra ID sign-in logs all flow into Log Analytics
- **Azure Policy guardrails** — deny public IP creation, restrict VM SKUs, enforce tagging
- **Auto-shutdown and TTL tags** — cost management by default; VMs shut down nightly
- **Three-tier lab guides** — each scenario has Guided 🟢, Hints 🟡, and Challenge 🔴 modes
- **MITRE ATT&CK mapped** — every scenario documents relevant technique IDs

---

## Architecture

```
┌──────────────────────────────────────────────┐
│                 Azure Tenant                 │
│  ┌────────────────────────────────────────┐  │
│  │         <RESOURCE_GROUP>                │  │
│  │                                        │  │
│  │   ┌──────┐  ┌───────┐  ┌───────────┐  │  │
│  │   │ DC01 │  │Bastion│  │    LAW    │  │  │
│  │   │(AD DS│  │(Ingress  │(Log Anal.)│  │  │
│  │   │ DNS) │  │ only) │  └───────────┘  │  │
│  │   └──────┘  └───────┘                 │  │
│  │         Base Infrastructure            │  │
│  │   ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │  │
│  │   ┌──────────┐  ┌─────┐  ┌───────┐   │  │
│  │   │ SP01     │  │BEC  │  │ AiTM  │...|  │
│  │   │(Module 1)│  │(M02)│  │ (M03) │   │  │
│  │   └──────────┘  └─────┘  └───────┘   │  │
│  │       Scenario Modules (disposable)    │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

All analyst access is via **Azure Bastion** (browser-based RDP/SSH). No VPN required.

---

## Training Programme

| Track | Level | Scenarios |
|-------|-------|-----------|
| 🟢 Foundations | Beginner | Lab Orientation, Log Sources, Alert Triage |
| 🟡 Threat Hunting | Intermediate | SharePoint Webshell, BEC Investigation |
| 🔴 Advanced | Advanced | AiTM Credential Theft, Cross-Cloud Federation Abuse |
| 🏆 Capstone | Expert | Full unguided IR scenario |

Each scenario is available in three modes:
- 🟢 **Guided** — step-by-step walkthrough with expected outputs
- 🟡 **Hints** — objectives provided with targeted nudges
- 🔴 **Challenge** — objectives only, no guidance

---

## Repository Structure

```
.
├── infra/
│   ├── base/          # Core infrastructure (VNet, Bastion, DC01, LAW)
│   ├── modules/       # Scenario modules (one directory per scenario)
│   └── policies/      # Azure Policy definitions
├── docs/
│   ├── admin-guide.md        # Deployment and operations guide
│   ├── student-quickstart.md # Getting started for analysts
│   ├── troubleshooting-log.md
│   └── lab-guide/
│       ├── 00-orientation.md
│       ├── 01-sharepoint-webshell.md
│       └── ...
└── scripts/
    └── reset-lab.sh   # One-command lab reset for instructors
```

---

## Quick Start

### Prerequisites
- Azure subscription with Contributor access
- Terraform v1.5+
- Azure CLI v2.50+

### Deploy

```bash
git clone https://github.com/birdforce14d/OpenRaptor.git
cd raptor/infra/base

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

Full deployment instructions: [docs/admin-guide.md](docs/admin-guide.md)

### Reset Lab for a New Student

```bash
# See docs/admin-guide.md for reset instructions
```

Destroys and rebuilds the scenario VM from a clean golden image. Takes approximately five minutes.

---

## Cost Estimate

| Resource | Estimated Cost/month* |
|---|---|
| DC01 (Standard_B2s) | ~$30 |
| SP01 (Standard_B4ms) | ~$60 |
| Kali01 (Standard_B2s) | ~$30 |
| Azure Bastion (Basic) | ~$140 |
| Log Analytics (~5 GB/day) | ~$15 |
| **Total** | **~$275/month** |

\* Based on Australia East region, 8 hours/day usage with auto-shutdown enabled. Costs vary by region and usage.

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
