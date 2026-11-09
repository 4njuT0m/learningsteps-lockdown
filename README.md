# LearningSteps Part 3: Locking Down a 2-Tier Azure Deployment

LearningSteps is a FastAPI app with a PostgreSQL database for keeping a daily learning journal. In Part 1 I built it by hand on two VMs, and in Part 2 I moved it to Terraform, Docker and AKS with a scanning pipeline. In this part I go back to a simple VM-based setup on purpose: I start from a deployment where security was ignored completely, and I harden it one layer at a time, doing most steps manually first so I understand what managed services would otherwise hide.

- the starting point is the intentionally insecure [CyberstepsDE/learningsteps-terraform](https://github.com/CyberstepsDE/learningsteps-terraform) "Base Deployment"
- every security fix is one phase, one commit and one Git tag, so the history shows each change on its own
- each phase has a write-up in `docs/` with the weakness, how an attacker would abuse it, the fix, and before/after proof

Key facts:

- Repository: `4njuT0m/learningsteps-lockdown`
- Part 1 repository: [`4njuT0m/learningsteps-azure-Project`](https://github.com/4njuT0m/learningsteps-azure-Project)
- Part 2 repository: [`4njuT0m/learningsteps-evolution`](https://github.com/4njuT0m/learningsteps-evolution)
- Region: West Europe

## Contents

- [Progress](#progress)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [What I did](#what-i-did)
- [Security decisions](#security-decisions)
- [Challenges](#challenges)
- [Known issues](#known-issues)
- [Key learnings](#key-learnings)
- [How to rebuild the environment](#how-to-rebuild-the-environment)
- [Cost and teardown](#cost-and-teardown)

## Progress

| Phase | Topic | Findings closed | Status | Tag | Write-up |
| --- | --- | --- | --- | --- | --- |
| 0 | Baseline assessment and top 5 attack scenarios | — (12 found) | Done | `phase-0-baseline` | [00-baseline-assessment.md](docs/00-baseline-assessment.md) |
| 1 | Management access: Entra ID SSH, SSH only from my IP | F-01, F-02 | Done | `phase-1-mgmt-access` | [01-management-access.md](docs/01-management-access.md) |
| 2 | TLS and web application firewall (NPMplus, Let's Encrypt, CrowdSec) | F-03, F-04, F-12 | Done | `phase-2-tls-waf` | [02-tls-waf.md](docs/02-tls-waf.md) |
| 3 | Identity-based API access (oauth2-proxy, Entra ID) | F-05 | Done | `phase-3-identity` | [03-identity.md](docs/03-identity.md) |
| 4 | Data isolation (VNet integration) + bonus: no plaintext secrets (Key Vault, managed identity) | F-06, F-08 | Planned | `phase-4-data-isolation` | — |
| 5 | Extra controls: least-privilege DB user, remote state, safe defaults, optional Sentinel test | F-07, F-09, F-10, F-11 | Planned | `phase-5-extra-controls` | — |
| 6 | Final documentation and clean redeploy test | — | Planned | `v1.0-final` | — |

## Architecture

### Before (baseline)

The baseline diagram and all findings are in [docs/00-baseline-assessment.md](docs/00-baseline-assessment.md).

### After (hardened)

_Added in Phase 7._

## Repository layout

| Path | What it is |
| --- | --- |
| `*.tf` | All Azure resources: network, VM, PostgreSQL, Sentinel and the auto-block playbook. |
| `deploy.py` | One-command deployment from the upstream project (login, SSH key, `terraform apply`, smoke test). |
| `scripts/` | cloud-init for the VM and the setup scripts for NPMplus, CrowdSec, oauth2-proxy and JSON logging. |
| `templates/block-ip-playbook.json` | Logic App that adds an NSG deny rule for an attacker's IP. |
| `handbook.md` | The upstream five-day walkthrough this project follows. |
| `docs/` | My phase write-ups and screenshots (`docs/screenshots/p3-<phase>-<nn>-<what>.png`). |
| `docs/ORIGINAL-README.md` | The upstream README, kept for reference. |

## What I did

### Phase 0 — Baseline assessment

- Created this repository from the upstream project and kept `upstream` as a second remote, so the first commit is the untouched baseline.
- Fixed `.gitignore`: upstream ignored the whole `docs/` folder, which would have kept every write-up and screenshot out of the repository. I also added rules for the files later phases create that hold secrets or real data (`azssh_config`, `npm.cookies`, `oauth2-proxy.cfg`, database dumps).
- Deployed the baseline with `deploy.py` (24 resources, all smoke tests passed) and recorded 12 findings with evidence, plus a top-5 attack scenario risk table. Details: [docs/00-baseline-assessment.md](docs/00-baseline-assessment.md).

### Phase 1 — Management access

- Showed the gap on my own VM: **132 SSH login attempts from 5 IPs**, the first only **29 minutes** after the VM was created.
- Switched to **Entra ID SSH login**: `Virtual Machine Administrator Login` role scoped to the VM; `az ssh` issues a certificate valid for about an hour instead of a key that never expires.
- Restricted the NSG rule `allow-ssh` from `*` to my IP through a validated Terraform variable, so my IP never lands in the repo.
- Proved it: SSH from another IP times out; my Entra ID login still works; no new attacks after the change. Details: [docs/01-management-access.md](docs/01-management-access.md).

### Phase 2 — TLS and WAF

- Changed the NPMplus admin password, which was the default published in the handbook (F-12); the NPMplus audit log shows `passwordChanged: true`.
- Published the app through NPMplus and showed the gap first: Wireshark showed every journal entry in plain HTTP.
- Enabled a **Let's Encrypt** certificate with Force HTTPS and HSTS (2 years): TLS 1.3, AES-256-GCM, post-quantum hybrid key exchange (X25519MLKEM768). HTTP now redirects to HTTPS, and Wireshark shows only encrypted records (plus the SNI hostname).
- Enabled the **CrowdSec WAF** (OWASP CRS): the same SQL injection and XSS payloads went from `200` to `403`, logged as `kind: waf` alerts.
- Documented that CrowdSec shares attack signals with its central API by default. Details: [docs/02-tls-waf.md](docs/02-tls-waf.md).

### Phase 3 — Identity gate

- Showed the gap: an anonymous `POST /entries` created data with no login.
- Registered a single-tenant Entra ID app (short-lived client secret, v2 tokens, `access_as_user` scope) and put **oauth2-proxy** in front of FastAPI through NPMplus Auth Request, with no app code changes.
- Found and fixed extra issues: the oauth2-proxy secrets file was world-readable (now `600`); the WAF blocked my own admin change; the gate looked saved in the GUI but was missing from the Nginx config; Entra tokens had no `email` claim.
- Proved it: anonymous and fake-token requests get `302` to the Microsoft login; a browser login and a real JWT get `200`. Decoded the JWT locally (RS256, audience = my API, 78-minute lifetime). Showed that identity and WAF complement each other: an anonymous attack gets `302`, the same attack from a signed-in session gets `403`. Details: [docs/03-identity.md](docs/03-identity.md).

## Security decisions

_Filled in per phase._

## Challenges

- `gh` (GitHub CLI) was not installed on Windows, so I created the empty repository on github.com and added it as `origin` by hand.
- The first `terraform apply` failed with **403 AuthorizationFailed**: the Azure CLI's default subscription was one where my account has no role. Fixed with `az account set --subscription "Anju Thomas - Sub"`. Lesson: being signed in (authentication) is not the same as being allowed to act (authorization).
- The second attempt failed with **401 RequestDisallowedByAzure**: Azure now requires MFA for every create, update or delete through Azure Resource Manager, including the CLI and Terraform. My CLI token had no MFA claim. Fixed by `az logout` and `az login --tenant …` with MFA.
- The Azure CLI's Windows login popup (WAM) offered "use this account everywhere", which registered my laptop with the Cybersteps tenant. I disconnected it in Windows Settings and switched the CLI to browser login (`az config set core.enable_broker_on_windows=false`).

## Known issues

_Filled in per phase._

## Key learnings

_Filled in per phase._

## How to rebuild the environment

Prerequisites: Python 3.8+, Terraform 1.5+, Azure CLI with the `ssh` extension (`az extension add --name ssh`), and Contributor or Owner on the subscription.

```powershell
git clone https://github.com/4njuT0m/learningsteps-lockdown
cd learningsteps-lockdown
python deploy.py --prefix <unique-name> --location westeurope
```

`deploy.py` asks for a PostgreSQL admin password and writes it to `terraform.tfvars`, which is git-ignored. The manual steps for each phase are in that phase's write-up.

## Cost and teardown

Deallocate the VM when not working on it:

```powershell
az vm deallocate --resource-group rg-<prefix> --name vm-<prefix>
az vm start      --resource-group rg-<prefix> --name vm-<prefix>
```

Remove everything at the end with `terraform destroy`.
