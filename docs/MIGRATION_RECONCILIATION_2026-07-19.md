# Migration reconciliation: 2026-07-19

This document is the authoritative status after the strict post-migration audit.
It supersedes intermediate rollback and staging notes in the earlier worklog.

## Deployment matrix

| Workload | Runtime on 212.116.115.150 | GitHub source | Persistent data | Off-host backup | Status |
| --- | --- | --- | --- | --- | --- |
| CRM | `/opt/crm-current` -> `/opt/crm-releases/5e9556a`; five healthy containers; zero restarts; port 8080 | `flycited2-dotcom/CRM_system`, `codex/stage-0-1` at `5e9556a6ba846d9ba79ae01a986e0ae4fb5b2b22` | Docker volumes for PostgreSQL, Redis, and uploads | `CRM-backups/212.116.115.150/2026-07-19/before-crm-5e9556a`; five hashes match | Running from a clean GitHub release |
| Sales Bot | `/opt/sales-bot-current` -> `/opt/sales-bot-releases/96e589a`; service active/enabled; zero restarts | `flycited2-dotcom/Telegram_Sales_meneger`, `agent/groq-egress-proxy` at `96e589a652a1667027874ce8800f6e1bbdcfe7f9` | `/var/lib/sales-bot/sales.db` and `products.json`; secret `.env` remains outside Git | `CRM-backups/212.116.115.150/2026-07-19/sales-bot-before-96e589a`; five hashes match | Running cleanly; Groq still uses the old VPS as temporary egress |
| Telegram-to-MAX | `/opt/tg-max-bridge`; service active/enabled; zero restarts | `flycited2-dotcom/from-telegram_to_max`, `main` at `3363b7aed8c99541f177ebb9b91bc9edab3388ae` | `.env`, `max_session.json`, rotating `bridge.log`, and `debug/`; runtime files are ignored by Git | `CRM-backups/212.116.115.150/2026-07-19/tg-max-before-3363b7a`; two hashes match | Running from clean Git; logging hardened and rotated |

## CRM verification

- The public URL is `http://212.116.115.150:8080/login`.
- `/api/health` returns `{"status":"ok","service":"crm-api"}`.
- Login returns HTTP 201; `/auth/me`, `/users`, `/clients`, and `/leads` return HTTP 200; logout returns HTTP 201.
- PostgreSQL has three completed Prisma migrations, one user, zero clients, and zero leads.
- API, web, nginx, PostgreSQL, and Redis all report `healthy` with zero restarts and use the `5e9556a` release directory.
- `CLIENT_UPLOAD_DIR` is `/app/uploads/clients`; a file written through `ClientsService` survived a forced API recreation with the same SHA-256 and was then removed.
- A normal `docker compose config` resolves the server-specific port to 8080.
- The clean release passes lint, 17 tests, API build, web build, and an isolated five-container end-to-end candidate test.
- A final current-state backup covering CRM, Sales Bot, and Telegram-to-MAX is stored at `CRM-backups/212.116.115.150/2026-07-19/final-state`; all 12 manifest entries match locally. The PostgreSQL dump listing, SQLite integrity, archives, and MAX-session JSON were also validated.

Current product limits are not migration failures: deals, tasks, offers, and messages are placeholder modules, and lead-to-deal conversion returns HTTP 501. Public lead webhooks and real Telegram/email notifications are also outside the current repository stage.

## Bot verification

- Sales Bot SQLite integrity is `ok`; the current snapshot has one conversation and eight orders. The external catalog contains 2,357 products.
- Sales Bot passed six tests, a Telegram `getMe` probe, and a real Groq completion through the restricted SOCKS relay. Post-start logs contain no errors, conflicts, Groq 403s, raw HTTP request URLs, or bot token.
- Telegram-to-MAX passed its logging test, Telegram `getMe`, valid MAX-session JSON, unit-file comparison, and post-start log checks. Its `.env`, session, current log, and debug files are mode 600.
- A previous live Telegram-to-MAX photo/caption flow completed successfully after the old poller was stopped. The latest code change only affects logging and file permissions.

## Old VPS 186.246.44.204

- CRM, Sales Bot, Telegram-to-MAX, and PM2 application services are inactive and disabled.
- There are no containers, Docker volumes, server databases, application cron jobs, or online PM2 processes.
- The server is still an active, restricted Groq egress relay for the Sales Bot on 212.116.115.150.
- The final delta archive is present on both servers and locally. SHA-256 is `aadc7c62aac21532e2c1a5786e263725df29cb28331691059c0173bc0f17cb4c`; the local old-server manifest has 11 entries and zero mismatches.
- Do not delete this VPS until Groq is moved to another supported-region host or replaced and a real Sales Bot completion succeeds without a connection to 186.246.44.204.

## Host 213.109.202.45

The public site is a separate static 36-screen CRM prototype backed by `mock-data.js`, not the Next/Nest/PostgreSQL GitHub CRM. HTTP-only inspection cannot prove whether old databases, uploads, containers, or source still exist on that host. Do not retire it without an SSH inventory and byte-preserving backup of its web root and any hidden application state.

## Remaining work

1. Replace the temporary Groq relay before deleting 186.246.44.204.
2. Assign a domain and HTTPS reverse proxy for CRM; port 8080 is currently public over plain HTTP.
3. Obtain SSH access to 213.109.202.45 if that host is also scheduled for retirement.
4. Decide separately whether to repair or disable the unrelated failing `crimea_watchdog.service` on the new server.
