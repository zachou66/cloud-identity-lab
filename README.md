# Cloud Identity & Access Lab — Microsoft Entra ID

> A 100% cloud-native IAM lab: cloud-only user provisioning automated with Microsoft Graph PowerShell, MFA and Conditional Access enforcement, self-service password reset, and SAML SSO to a SaaS application. **No servers, no VMs, no on-prem dependency.**

> ⚙️ **Status: in progress.** This README is built to document itself phase by phase. Each phase below carries its capture checklist and a write-up I complete the moment that phase is done — so every claim here is backed by a screenshot or log in this repo. Phases not yet checked off are not yet done.

## Why This Project

My [Active Directory homelab](https://github.com/zachou66/active-directory-homelab) proved on-prem and hybrid identity. This lab proves the other half: a cloud-only tenant managed entirely through Microsoft Entra ID — the direction most organizations are moving. It closes the MFA / SSO / Conditional Access gaps directly, pairs with AZ-900, and adds a pure-cloud project to the set.

## Environment

- **Tenant:** `zaolab.onmicrosoft.com` with a **Microsoft Entra ID P1** license (included in M365 Business Premium). Conditional Access, dynamic groups, and SSPR all require P1.
- **Identity model:** cloud-only users created directly in Entra ID — never synced — under two new departments (**Marketing**, **Operations**) so they can't collide with the synced AD-lab users already in the tenant.
- **Access:** a Global Administrator login, a browser, and a phone for Microsoft Authenticator.
- **Cost:** $0 beyond licensing — no compute is deployed at any point.

## Design Decisions

- **Cloud-only users, new departments.** New users are created directly in Entra ID under `Marketing` and `Operations`, isolated from the synced AD-lab users.
- **Break-glass account.** One emergency Global Admin (`bg.admin`) with a long, offline-stored password, **excluded from every Conditional Access policy** — standard enterprise lockout insurance and a deliberate, documentable choice.
- **Report-only before enforce.** Every Conditional Access policy ships in report-only mode, is validated against the sign-in logs, then switched on. This mirrors a production rollout.
- **Optional: cut the cord.** Directory sync from the old bare-metal DC can be decommissioned (disable dirsync via Graph) — only if the hybrid lab is truly finished, since it can't be re-enabled for ~72 hours. A decision, not a requirement.

## Naming Conventions

| Object | Convention | Example |
| --- | --- | --- |
| Cloud user | `firstname.lastname` | `maya.torres` |
| Role group (assigned) | `CL-R-<Dept>` | `CL-R-Marketing` |
| Dynamic group | `CL-DYN-<Dept>` | `CL-DYN-Marketing` |
| CA policy | `CA## - <Effect> - <Scope>` | `CA01 - Require MFA - All users` |
| Break-glass | `bg.admin` | — |

**Screenshot naming:** `phaseN_what-it-shows.png` (e.g. `phase3_ca-require-mfa.png`) — they sort in order and describe themselves. Every capture below gives the exact filename to use.

## Project Phases

| Phase | Focus | Status |
| --- | --- | --- |
| **0** | Licensing check, break-glass account | ☐ Not started |
| **1** | Cloud-only users and groups (incl. one dynamic group) | ☐ Not started |
| **2** | Graph PowerShell provisioning automation | ☐ Not started |
| **3** | MFA, SSPR, Conditional Access | ☐ Not started |
| **4** | SAML SSO to a SaaS app | ☐ Not started |

---

## Phase 0 — Tenant Prep & Safety

**Objective:** confirm licensing and create an emergency break-glass admin before any policy work.

1. Sign in at `entra.microsoft.com` → **Billing → Licenses** → confirm Entra ID P1 is present (or start the P2 trial).
2. Create `bg.admin`: Global Administrator role, 30+ character random password stored offline, no other use. It gets excluded from every CA policy in Phase 3.
3. Do **not** touch security defaults yet — that happens in Phase 3, right before custom CA replaces them.

**Captures for this phase**
- [ ] `screenshots/phase0_license-check.png` — licenses page showing P1/P2 active
- [ ] `screenshots/phase0_break-glass-admin.png` — `bg.admin` Assigned roles showing Global Administrator

> **Write-up (fill in when this phase is done):** 2–3 sentences — what P1 unlocks, why a break-glass account exists, and that it's excluded from CA on purpose. Embed both screenshots, then flip Phase 0 to ☑ in the table above.

---

## Phase 1 — Cloud Identity Foundation

**Objective:** build cloud-only groups and users, including a dynamic group that auto-fills by department.

1. Create assigned security groups `CL-R-Marketing` and `CL-R-Operations`.
2. Create dynamic group `CL-DYN-Marketing` with rule `user.department -eq "Marketing"`.
3. Create **one** user manually (e.g. `maya.torres`, Department = Marketing, set Usage location) to learn the flow before automating.
4. Confirm the dynamic group picked her up automatically.
5. *(Optional, roughly irreversible)* Decommission directory sync — see Design Decisions.

**Captures for this phase**
- [ ] `screenshots/phase1_groups-list.png` — groups list showing both `CL-R-*` groups
- [ ] `screenshots/phase1_dynamic-rule.png` — membership-rule builder showing the rule
- [ ] `screenshots/phase1_user-profile.png` — `maya.torres` profile with Department populated
- [ ] `screenshots/phase1_dynamic-members.png` — dynamic group members showing the user

> **Write-up (fill in when this phase is done):** explain the difference between an assigned group and a dynamic group in your own words, and why dynamic membership scales. Embed the four shots, then flip to ☑.

---

## Phase 2 — Graph PowerShell Provisioning

**Objective:** automate cloud user onboarding from a CSV, idempotently, with logging. The cloud twin of the AD lab's `Onboarding.ps1`, rebuilt on the Microsoft Graph PowerShell SDK.

**Script:** [`Provisioning/Onboard-CloudUsers.ps1`](Provisioning/Onboard-CloudUsers.ps1) — requirements it implements:

- Connects with `Connect-MgGraph` using `User.ReadWrite.All` and `Group.ReadWrite.All` scopes.
- Reads [`Provisioning/users.csv`](Provisioning/users.csv): `FirstName, LastName, Department, JobTitle, UsageLocation, RoleGroups`.
- Derives UPN `firstname.lastname@zaolab.onmicrosoft.com`.
- **Idempotent:** checks for an existing user first; skips with a warning instead of duplicating.
- Creates the user enabled, with a random temp password and forced change at first sign-in.
- Adds the user to each group in `RoleGroups` (semicolon-separated).
- Logs everything via `Start-Transcript`; per-user `try/catch`.

**Validation (the idempotency proof — the strongest Phase 2 artifact):** run it twice with the same 5-row CSV. Run 1 shows `CREATED`; run 2 shows `SKIPPED` for every row.

**Evidence & captures for this phase**
- [ ] `Provisioning/sample-logs/run1-created.txt` — transcript of the first run (all CREATED)
- [ ] `Provisioning/sample-logs/run2-skipped.txt` — transcript of the second run (all SKIPPED)
- [ ] `screenshots/phase2_users-created.png` — Entra users list showing the new cloud users after run 1

> **Write-up (fill in when this phase is done):** explain what "idempotent" means and why it matters (safe to re-run, no duplicates). Link the script, the CSV, and both transcripts, then flip to ☑.

---

## Phase 3 — Authentication Hardening

**Objective:** enforce MFA and block legacy auth with Conditional Access; enable self-service password reset.

1. Enable **SSPR** for `CL-R-Marketing` (Authenticator + email methods).
2. Register MFA for a test user at `aka.ms/mfasetup` (Microsoft Authenticator).
3. **Now** disable security defaults (Entra ID → Properties → Manage security defaults) — custom CA replaces them.
4. Create `CA01 - Require MFA - All users`, **excluding `bg.admin`** → start **report-only** → review sign-in logs → switch On.
5. Create `CA02 - Block legacy auth - All users` (target legacy client apps) → On.
6. Create `CA03 - Require MFA - Admins` (target directory roles) → On.
7. Test, and capture the proof each test produces (see checklist).

**Lockout safety:** keep a working Global Admin session open in a second browser the whole time, exclude `bg.admin` everywhere, and never skip report-only.

**Captures for this phase**
- [ ] `screenshots/phase3_sspr-enabled.png` — SSPR settings scoped to the group
- [ ] `screenshots/phase3_ca-require-mfa.png` — CA01 showing the MFA grant and the `bg.admin` exclusion
- [ ] `screenshots/phase3_ca-policy-list.png` — all three policies listed with their states
- [ ] `screenshots/phase3_mfa-prompt.png` — fresh/InPrivate sign-in as a cloud user hitting the MFA prompt
- [ ] `screenshots/phase3_signin-log-mfa.png` — a completed sign-in in the logs showing MFA satisfied
- [ ] `screenshots/phase3_whatif-breakglass.png` — **What If** against `bg.admin` showing no policy applies

> **Write-up (fill in when this phase is done):** explain *why report-only first* and the difference between security defaults and Conditional Access, in your own words. Embed the shots, then flip to ☑.

---

## Phase 4 — SAML SSO to a SaaS App

**Objective:** stand up SAML single sign-on to a SaaS app with group-based access.

1. Entra ID → **Enterprise applications → New application → gallery → Microsoft Entra SAML Toolkit**.
2. Configure SAML SSO per the app tutorial values; assign `CL-R-Marketing`.
3. Sign in through **My Apps** (`myapps.microsoft.com`) as a Marketing user → app opens via SSO.
4. *(Bonus)* Add a custom claim (e.g. department) and show it in the token.

**Captures for this phase**
- [ ] `screenshots/phase4_saml-config.png` — the SAML SSO configuration page
- [ ] `screenshots/phase4_sso-success.png` — the app opened after SSO
- [ ] `screenshots/phase4_myapps-tile.png` — the app tile in My Apps
- [ ] `screenshots/phase4_custom-claim.png` — *(bonus)* the custom claim in the token

> **Write-up (fill in when this phase is done):** explain SSO in one breath (user → app → redirect to Entra → Entra authenticates → signed SAML token → app trusts it). Embed the shots, then flip to ☑.

---

## Roadmap / Stretch (honest about licensing)

- **Require compliant device** — CA policy + cloud-native Intune enrollment; needs a spare Windows PC/VM. Optional.
- **Risk-based Conditional Access** (Identity Protection) — needs P2 (free 30-day trial).
- **Access reviews / PIM** — P2.
- **Decommission directory sync** if not done in Phase 1.

## What This Earns (resume bullets — claim only after completion)

- Built a cloud-only identity environment in Microsoft Entra ID, automating CSV-driven user provisioning with the Microsoft Graph PowerShell SDK (idempotent, transcript-logged).
- Enforced MFA and blocked legacy authentication with Conditional Access policies, rolled out report-only first and validated through sign-in log analysis.
- Configured SAML single sign-on to a SaaS application with group-based assignment.
- Implemented self-service password reset and an emergency-access (break-glass) admin account excluded from Conditional Access.

*Fill in real counts at the end (e.g. number of CA policies) — only numbers that exist.*

## Interview Talking Points

- **Why report-only first:** CA can lock out every user including admins; report-only shows what *would* happen in the sign-in logs before enforcement.
- **Security defaults vs Conditional Access:** defaults are Microsoft's one-size preset; CA is the granular replacement — you can't run both.
- **SSO in one breath:** user hits the app → redirect to Entra ID → Entra authenticates (password + MFA) → Entra returns a signed SAML token → app trusts it and signs the user in.
- **Why break-glass exists:** if MFA or CA misfires, one excluded account is the difference between a fix and a locked tenant.

## Author

**Zachary Ouldsfiya** — UMass Boston · BS Information Technology (System Administration Track) · 2026
CompTIA Security+ · Microsoft AZ-900 (in progress)
ouldsfiyazachary@gmail.com
