# Server inventory: 186.246.44.204

Audit date: 2026-07-19

## Decision

Do not delete the server yet. All application pollers have moved to the new VPS,
but this host still supplies the restricted Groq egress path used by Sales Bot.
See `docs/MIGRATION_RECONCILIATION_2026-07-19.md` for the authoritative state.

## Application found during the initial audit

- `sales_bot.service`: active, enabled, PID 698, no recorded restarts.
- Working directory: `/root/sales_bot`.
- Main state database: `/root/sales_bot/data/sales.db` (32768 bytes, last modified
  2026-07-17 23:31 server time).
- The Git checkout is at commit
  `423863cef3c46eabb1ddfe70aa590da804d76ff8` and has three local changes:
  `data/products.json`, `sales_agent.py`, and untracked `_reset.py`.

At audit time, the new server did not contain `sales_bot.service`. It was migrated
later on 2026-07-19.

## Migrated or stopped applications

- `/opt/crm`: clean Git checkout at
  `9d83d2e01ba821728f9b21e7bafea2601ad5b116`. No CRM containers or Docker
  volumes remain active on this server.
- `/opt/tg-max-bridge`: clean Git checkout at
  `99b598cc8effff4efb400084f80e5cf102480903`.
  `tg-max-bridge.service` is inactive on this server after the successful cutover.
- PM2 is installed and enabled, but its only listed application,
  `claude-telegram-bridge`, is stopped.

## Other stored projects and data

- `/root/sales_bot_pro`: inactive source copy without Git metadata. It contains
  `data/sales.db` (118784 bytes) and `data/sales_server.db` (24576 bytes).
- `/root/hotels_bot`: inactive, clean Git checkout at
  `294f13a96193ec2ac1a6ced37d2ae81ca28371fb`.
- `/root/hotels_sbor_baza`: inactive, clean Git checkout at the same commit; an
  environment file is present.
- `/home/user/VPS-ClaudeCode`: inactive Node.js project with an environment file.
- `/home/alex/tg-max-bridge-backup-20260504-210019`: older bridge backup.
- `/root/archives/hotel_lead_bot-pre-migration-20260515-234912.tgz`.
- `/root/archives/sales_bot_pro-removed-20260516-152429.tar.gz`.
- Two older Telegram-to-MAX archives are stored under `/home/alex`.

Environment and session files were identified by name only. Their contents were
not printed during the audit.

## Host state

- Ubuntu 25.10, one 40 GB virtual disk, about 18 GB used and 20 GB free.
- No running Docker containers and no Docker volumes. CRM-related images remain.
- No active Nginx, Apache, Caddy, PostgreSQL, MySQL, MariaDB, Redis, or MongoDB
  service.
- Listening TCP ports are `22` and `443`; both are SSH endpoints.
- No active application cron jobs, custom timers, screen sessions, tmux sessions,
  or queued `at` jobs were found.

## Current backup coverage

At initial audit time, the local backup directory contained only:

- `crm-186.246.44.204-2026-07-19.tar.gz`
- `tg-max-bridge-186.246.44.204-2026-07-19.tar.gz`

Sales Bot and the other stored projects were subsequently archived and verified.

## Completion status

1. Completed: CRM, Sales Bot, Telegram-to-MAX, and all inactive project data are
   covered by verified local archives and manifests.
2. Completed: old application services are inactive and disabled; the new Sales
   Bot poller is active from clean GitHub release `96e589a`.
3. Completed: the final delta archive covers the files found after the first
   manifest and matches locally and on both VPS hosts.
4. Blocked: replace the Groq relay and verify a real completion without any
   connection to this server before deleting it in the hosting panel.
