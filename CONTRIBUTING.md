# Contributing to Project Raptor

Thank you for your interest in contributing to the CIRT Cyber Range. This document outlines the process for contributing scenarios, fixes, and improvements.

---

## Ways to Contribute

- **New scenario modules** — threat scenarios with matching lab guides
- **Lab guide improvements** — clarity, accuracy, additional hints
- **Infrastructure fixes** — Terraform bugs, hardening, cost optimisation
- **Documentation** — admin guide, student guides, architecture docs
- **Bug reports** — open an issue with reproduction steps

---

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/<your-username>/raptor.git`
3. Create a feature branch: `git checkout -b feature/your-change`
4. Make your changes (see guidelines below)
5. Test your changes
6. Submit a pull request against the `main` branch

---

## Contribution Guidelines

### All contributions
- No secrets, credentials, or internal infrastructure references
- Follow existing naming conventions and directory structure
- Update relevant documentation alongside code changes

### Infrastructure (Terraform)
- Run `terraform validate` and `terraform fmt` before submitting
- All VMs must be private-only (no public IPs)
- Tag all scenario resources with `module` and `ttl` tags
- Test with `terraform plan` against a clean subscription

### Scenario modules
Each new scenario must include:
- [ ] Terraform module in `infra/modules/<scenario-name>/`
- [ ] Lab guide in `docs/lab-guide/<nn>-<scenario-name>.md`
- [ ] MITRE ATT&CK technique IDs documented in the lab guide
- [ ] Three difficulty modes: Guided 🟢, Hints 🟡, Challenge 🔴
- [ ] Incident report template
- [ ] TTL tagging for auto-destroy
- [ ] Smoke test or verification steps

### Lab guides
- Write for an analyst audience — assume familiarity with Azure and KQL basics
- Use the existing module structure (scenario brief, objectives, walkthrough, debrief)
- All KQL queries must be tested and produce expected output in the lab environment
- Narrative framing should be realistic but use the fictional NORCA company context

---

## Pull Request Process

1. Describe what your change does and why
2. Reference any related issues
3. Confirm you have tested the change
4. A maintainer will review within 5 business days

---

## Code of Conduct

Be respectful and constructive. We are all here to learn and improve detection capabilities. Harassment or hostile behaviour will not be tolerated.

---

## Questions?

Open a [GitHub issue](https://github.com/birdforce14d/OpenRaptor/issues) for questions, ideas, or discussion.
