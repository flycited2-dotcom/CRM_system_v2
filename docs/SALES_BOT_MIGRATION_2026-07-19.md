# Sales Bot migration: 186.246.44.204 to 212.116.115.150

Migration date: 2026-07-19

## Result

Final reconciliation update: production now runs from clean release
`/opt/sales-bot-releases/96e589a` through `/opt/sales-bot-current`. GitHub branch
`agent/groq-egress-proxy` points to
`96e589a652a1667027874ce8800f6e1bbdcfe7f9`. Mutable state lives separately in
`/var/lib/sales-bot`; SQLite integrity is `ok`, with one conversation and eight
orders, and the catalog contains 2,357 products. The service and Groq tunnel are
active/enabled with zero restarts. Six tests, Telegram `getMe`, and a Groq
completion passed. HTTP client INFO logs are disabled so bot-token URLs are no
longer written to the journal.

The current off-host snapshot is
`C:\Users\user\Documents\CRM-backups\212.116.115.150\2026-07-19\sales-bot-before-96e589a`;
its five-entry manifest has zero mismatches.

The Telegram Sales Bot application, Python environment, and final SQLite state
are now running on `212.116.115.150`. The old poller is disabled, so only the new
server consumes Telegram updates.

The first cutover had been rolled back because Groq returned HTTP 403 from the new
server's RU outbound addresses. A second cutover succeeded after adding a narrow
temporary egress path through the old NL server:

- `groq-egress-tunnel.service` runs an SSH dynamic SOCKS listener only on
  `127.0.0.1:11080` on the new server.
- Its dedicated SSH key is accepted only from `212.116.115.150`; forwarding on
  the old server is restricted to Groq HTTPS destinations.
- An authenticated Groq models request returns HTTP 403 directly and HTTP 200
  through the tunnel. A non-Groq destination is rejected.
- A real `SalesAgent` SDK chat completion through the tunnel succeeded with
  `llama-3.3-70b-versatile`.
- After startup, the new journal recorded eight successful `getUpdates` and two
  successful `getMe` requests, with zero Telegram non-200 responses, Groq 403s,
  polling conflicts, tracebacks, or error lines.
- The final live test received a new user message on the new poller, called Groq
  successfully over the tunnel, sent the Telegram reply with HTTP 200, and saved
  the updated conversation on the new server. The flow logged zero Groq 403s,
  polling conflicts, tracebacks, or error lines.
- A later message exposed an unrelated transient Telegram timeout while sending
  the cosmetic typing indicator. Because that call was outside the handler's
  protected processing block, the message stopped before Groq. Commit `ceec45b`
  now logs this condition as a warning and continues processing; its regression
  test first reproduced the exact `telegram.error.TimedOut` and then passed.
- After deploying that fix, all four tests passed and the post-restart journal
  recorded six successful `getUpdates` and two successful `getMe` requests with
  zero non-200 responses, Groq 403s, conflicts, tracebacks, errors, or warnings.
- Current poller: new `sales_bot.service` is active and enabled with zero
  restarts; old `sales_bot.service` is inactive and disabled with PID 0.

The application migration is complete, but the old VPS still provides the
temporary Groq egress path and therefore must not be deleted yet. Replace it with
a small supported-region VPS/proxy, or replace Groq, before shutting it down.

## Data verification

Before cutover, SHA-256 values matched between the old and new servers for:

- `.env`
- `requirements.txt`
- `config.py`
- `database.py`
- `main.py`
- `sales_agent.py`
- `data/products.json`
- `data/sales.db`
- `/etc/systemd/system/sales_bot.service`

After the old service was stopped, the final state archive was copied locally and
to the new server. Its SHA-256 matched at all three locations.

For the successful second cutover, the old poller was stopped before the database
snapshot was made. SQLite `integrity_check` returned `ok`; the snapshot contains
one conversation and three orders. Its SHA-256 matched on the old server, the
local backup, and the installed new-server database:

`60c333ee486fb2ad75973fd3ee4c66c0fbd6ba9cb0a20566e442f2a278eb9316`

An online backup taken after the live incoming-message test also passed
`integrity_check`. It contains one conversation, 24 retained history messages,
and three orders; its server and local SHA-256 is:

`919cb23fd13141be793f87503b7e40a4b5d7fe1188961a303cd4ebf5b0822ba6`

## Local backup artifacts

Directory:
`C:\Users\user\Documents\CRM-backups\186.246.44.204\2026-07-19`

- Full pre-cutover snapshot:
  `sales-bot-precutover-186.246.44.204-2026-07-19.tar.gz`
  - SHA-256: `ba042d94bd08d66a4136d67fb819b396a881f1829e8f18baa084e9691e64b411`
- Final source, configuration, Git, and data state:
  `sales-bot-final-state-186.246.44.204-2026-07-19.tar.gz`
  - SHA-256: `42cf3f1c5c262e7f60f4c7850c1e0c001fc57c90cdc0dc8144724d52e62ffc44`
- Exact installed package list:
  `sales-bot-requirements-freeze-2026-07-19.txt`
  - SHA-256: `e8cea41ce2df170245fca189361b38920d1434589873020ced1f50ce7f9a4f23`
- Other inactive projects, databases, archives, PM2 state, and cron metadata:
  `extra-projects-and-config-186.246.44.204-2026-07-19.tar.gz`
  - SHA-256: `35e1907bb9bc94f320ab013aa9ff1858be543c2865d5bcf069ff5605d9a63a35`
- Post-test database returned during rollback:
  `sales-bot-db-after-cutover-test-2026-07-19.sqlite`
  - SHA-256: `87c8e5fd905bd3516101a9a82c44a1c44b41865cf22a9bd6c16dabfc546e70aa`
- Final database used for the successful cutover:
  `sales-bot-db-final-cutover-20260719T113246Z.sqlite`
  - SHA-256: `60c333ee486fb2ad75973fd3ee4c66c0fbd6ba9cb0a20566e442f2a278eb9316`
- Database after the successful live incoming-message test:
  `sales-bot-db-post-live-e2e-20260719T114000Z.sqlite`
  - SHA-256: `919cb23fd13141be793f87503b7e40a4b5d7fe1188961a303cd4ebf5b0822ba6`
- Installed package list after adding SOCKS support:
  `sales-bot-requirements-freeze-post-groq-proxy-2026-07-19.txt`
  - SHA-256: `67a4e172ffc26a2d79104ec6b58a4b140ea64142472694899c049396abfa0b54`
- `SHA256SUMS.txt` contains the complete local manifest.

## Runtime compatibility

The old virtual environment used Python 3.13.7. The new server provides Python
3.12.3, so the old environment was preserved as
`/root/sales_bot/venv.source-python3.13` and a new environment was built with the
same 43 pinned package versions. All production modules compile on the new host.
The proxy deployment adds `socksio==1.0.0`; the post-proxy freeze contains 45
installed package entries and is stored with the local backups.

The untracked `_reset.py` already had an unterminated string on the old server and
is not imported by the running application. It remains in the byte-preserving
archive but was intentionally excluded from the GitHub source snapshot.

## GitHub snapshot

- Repository: `flycited2-dotcom/Telegram_Sales_meneger`
- Branch: `backup/server-186-sales-bot-2026-07-19`
- Commit: `ce98d31b886946795a18379e120770389628161f`
- Included: `data/products.json` and `sales_agent.py` from the production server.
- Secrets, `.env`, SQLite data, and the broken `_reset.py` were not committed.

The Groq proxy implementation is also published separately:

- Branch: `agent/groq-egress-proxy`
- Proxy commit: `998f2033474b2a7cc81592cc0289bc8310ec006e`
- Current commit: `ceec45be967ee2ccf7ee2e015bf4ca7a81570fa9`
  (`Continue replies when typing status times out`)
- Included: optional `GROQ_PROXY_URL` support, tests, the SOCKS dependency, and
  systemd deployment files, plus the typing-timeout regression fix. No API key,
  Telegram token, or private SSH key is in Git.

## Current service placement

- Old `sales_bot.service`: inactive, disabled, PID 0.
- New `sales_bot.service`: active and enabled; PID 156342 and zero restarts at
  the completed startup check.
- New `groq-egress-tunnel.service`: active and enabled; PID 149336 and zero
  restarts at the completed startup check.
- Old `tg-max-bridge.service`: inactive and disabled.
- Old `pm2-root.service`: inactive and disabled; PM2 had zero online applications.
- The application and database are on the new VPS. Only Groq network egress still
  depends on the old VPS.

The hosting server itself has not been deleted.
