# Worklog: CRM

## Current goal
The project now covers only the CRM system: its operation, its integrations, and tender parsing. The single open infrastructure task is resolving the public plain-HTTP endpoint on port 8080 (domain + HTTPS).

## State (updated 2026-07-20)
- Done: the server migration is closed by owner decision. Everything was moved, cleaned, and re-verified; the authoritative record is `docs/MIGRATION_RECONCILIATION_2026-07-19.md`, and the final verified backups (12/12 SHA-256 matches) are at `C:\Users\user\Documents\CRM-backups\212.116.115.150\2026-07-19\final-state`.
- Done: CRM production runs clean GitHub release `5e9556a` (`flycited2-dotcom/CRM_system`, branch `codex/stage-0-1`) at `http://212.116.115.150:8080`; five healthy containers, zero restarts; login, API, and upload persistence verified.
- Done: master assignment for Codex agents written at `docs/TZ_CODEX_CRM.md` — 14 epics (E0–E13) covering engineering base, core review, RBAC, deals/tasks/offers/messages, notifications, email, Telegram, site webhooks, tender module + parsing, dashboards, and UI polish to the prototype's visual language; waves, DoD (lint + tests + builds), and blocked-input placeholders included.
- Done: owner supplied the free domain `oasis.com.ru` for the CRM (currently empty — acceptable).
- Next: owner creates DNS A record(s) `crm.oasis.com.ru` (and optionally the apex) → `212.116.115.150`; then configure a server block in the existing new-server Nginx + Let's Encrypt, and close public port 8080.
- Next: copy `crm_project_docs` (10 files) + `docs/TZ_CODEX_CRM.md` into the `CRM_system` repo (`docs/specs/`) so Codex agents can read them (task E0.1; can also be done locally via authenticated `gh`).
- Next: owner will supply integration inputs: site list/domains, SMTP/IMAP, Telegram bot token, tender sources (TZ §8).

## Decisions
- 2026-07-19: the owner closed the migration plan; all migration follow-ups (Groq relay replacement, `213.109.202.45` inventory, `crimea_watchdog.service`) are removed from this project's scope. Only the port-8080/HTTPS item remains. Rejected: keeping those threads here — they belong to server operations, not the CRM project.
- 2026-07-19: new-server ports 80/443 are occupied by an existing Nginx serving unrelated bots; CRM stays on host port 8080 until a domain/reverse-proxy route is chosen.

## Gotchas
- Do NOT power off or delete `186.246.44.204` without a separate check: it still acts as the restricted Groq egress relay for the live Sales Bot on `212.116.115.150`. The bot is outside this project's scope, but deleting that VPS today would break it.
- Known CRM product gaps at `5e9556a` (pre-existing, not migration defects): deals, tasks, offers, and messages are placeholder modules; lead-to-deal conversion returns HTTP 501; the declared lint command is nonfunctional because no ESLint 9 config exists.

## Open threads
- Port 8080: CRM is public over plain HTTP on `212.116.115.150:8080`; needs a domain + HTTPS (or the port closed to the internet).
- Tender parsing: requirements and data flow into the CRM are not yet specified.
