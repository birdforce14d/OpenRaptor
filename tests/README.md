# OpenRaptor — Automated Test Suite

_OD@CIRT.APAC internal. Run order matters — see pipeline below._

## Test Scripts

| Script | Where to run | What it tests |
|--------|-------------|---------------|
| `test-deploy.sh` | Orchestrator / GitHub Actions | Azure infrastructure: VMs, networking, Bastion, DNS, LAW — all provisioned and running |
| `test-lab.sh` | Kali01 or orchestrator | End-to-end Module 01 scenario: webshell upload → execution → evidence trail in IIS/Event/ULS logs |
| `test-reset.sh` | Orchestrator / GitHub Actions | Post-reset clean state: webshell removed, IIS logs cleared, SP01 healthy |

## Run Order

```
terraform apply
    │
    ▼
test-deploy.sh          ← Infrastructure gate: all VMs/networking up?
    │
    ▼
lab_01_setup.ps1        ← Stage accounts + toolkit
    │
    ▼
test-lab.sh             ← Scenario gate: does the attack generate evidence?
    │
    ▼
lab_01_reset.ps1        ← Reset SP01 to clean state
    │
    ▼
test-reset.sh           ← Clean state gate: safe to hand to next student?
```

## Quick Run (local)

```bash
# Set credentials
export ARM_SUBSCRIPTION_ID="68eae5b1-efab-4a2f-a117-c36bbbd72c60"
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."
export ADMIN_PASS="CirtApacAdm!n2026"
export STUDENT_PASS="CirtApacStudent2026"

# Log in
az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID"

# Run each gate
bash tests/test-deploy.sh
bash tests/test-lab.sh
bash tests/test-reset.sh
```

## CI Pipeline (GitHub Actions)

Pipeline: `.github/workflows/test-lab.yml`

| Trigger | Jobs run |
|---------|----------|
| PR to main | `tf-validate` + `tf-plan` (no apply) |
| Push to main | Full pipeline: validate → plan → apply → test-deploy → test-lab → test-reset |
| Nightly (02:00 UTC) | `test-deploy` only (smoke — no changes) |
| Manual dispatch | Configurable: `smoke`, `full`, `lab-only`, `reset-only` |

### Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `ARM_CLIENT_ID` | SP client ID |
| `ARM_CLIENT_SECRET` | SP client secret |
| `ARM_TENANT_ID` | Customer tenant ID |
| `ARM_SUBSCRIPTION_ID` | Customer subscription ID |
| `ADMIN_PASSWORD` | `CirtApacAdm!n2026` |
| `STUDENT_PASSWORD` | `CirtApacStudent2026` |

### Environments

Create a `lab-deploy` GitHub Environment with required reviewers to gate `terraform apply`.
