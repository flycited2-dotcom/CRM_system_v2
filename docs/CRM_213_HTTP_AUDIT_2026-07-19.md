# Read-only HTTP audit: 213.109.202.45

Date: 2026-07-19

## Scope

- Audited only resources linked by the public HTML and JavaScript.
- Used only GET/HEAD requests, plus GET/HEAD for `/api/health`.
- Did not use SSH, scan ports, submit forms, authenticate, or send mutating requests.
- Mock records were not printed; only collection names and counts were recorded.

## 1. Public page and asset inventory

The root returns a 312-byte static HTML document with a zero-delay meta refresh to
`/app/dashboard-owner.html`. It is not an HTTP redirect.

Discovered and verified with HTTP 200:

- 36 functional screens.
- 2 shell fragments: sidebar and topbar.
- 7 modal fragments: command palette and create client/lead/deal/task/offer/tender.
- 1 root redirect document.
- 7 local assets: 2 CSS files and 5 JavaScript files.

This is 46 successful HTML documents and 7 successful local assets. The Chart.js
bundle references `chart.umd.min.js.map`, but that source map returns HTTP 404.

Functional screen modules:

| Module | Screens |
| --- | ---: |
| Login | 1 |
| Owner/manager dashboards | 2 |
| Clients | 2 |
| Leads | 2 |
| Deals | 4 |
| Tasks | 5 |
| Commercial offers | 2 |
| Tenders | 3 |
| Employees | 2 |
| Reports | 8 |
| Settings | 5 |

Local assets:

- `/assets/css/app.css`
- `/assets/css/tokens.css`
- `/assets/js/chart.umd.min.js`
- `/assets/js/mock-data.js`
- `/assets/js/relative-date.js`
- `/assets/js/shell.js`
- `/assets/js/widgets.js`

External presentation dependencies are Tailwind CDN, Google Fonts, and Lucide.
Chart.js is bundled locally. No CRM version, commit, repository URL, build ID, or
source map was exposed. The only dependency version marker found was Chart.js
`4.5.1`.

The HTTP metadata is only a weak deployment clue: the root file reports
`Last-Modified: 2026-05-16`, while the owner dashboard and mock dataset report
`Last-Modified: 2026-06-12`. These timestamps do not identify a Git commit.

Key response fingerprints:

- `/`: SHA-256 `19d3e565a6b2e13bdd70218672416133951ceff6e138a5040296ece6ffa435cb`
- `/app/dashboard-owner.html`: SHA-256 `2b70561e40cfda6172fad58d52c95032b5075657ef826fd902721e5786d288ba`
- `/assets/js/mock-data.js`: SHA-256 `58446b051552947a345e5330db7c572ad842049d85f71f7e369f4f0e66c261f1`

## 2. Backend and state evidence

The currently exposed site is a static mock, not a UI connected to a persistent
CRM backend.

Evidence:

- `/api/health` returns nginx HTTP 404 with HTML, not the CRM JSON health response.
- Across all discovered application HTML and JavaScript, there are no XHR, Axios,
  WebSocket, EventSource, beacon, or API fetch calls.
- The only two `fetch()` call sites load static sidebar and modal HTML fragments.
- All 35 non-login functional screens include `/assets/js/mock-data.js`.
- The login button does not authenticate: it stores `crm.role=owner` in
  `localStorage` and navigates to the owner dashboard.
- `localStorage` is otherwise used only to read/remove that role; no CRM entities
  are persisted in browser storage.
- Create modals contain no `<form>`, form action, submit handler, or inline script.
  Their action buttons only carry the modal-close attribute.
- Four `/api/webhooks/...` strings appear only as displayed endpoint metadata on
  the site-token settings screen. No code calls them.

`window.MOCK` exposes one helper and twelve arrays:

| Collection | Count |
| --- | ---: |
| Clients | 24 |
| Contacts | 40 |
| Deal products | 52 |
| Deals | 22 |
| Leads | 18 |
| Messages | 15 |
| Notifications | 8 |
| Offers | 12 |
| Tasks | 35 |
| Tenders | 7 |
| Users | 8 |
| Work sessions | 56 |

This conclusion applies to the public application surface. A detached backend,
database, or Docker volume could still exist on the host and cannot be detected
by the permitted HTTP-only audit.

## 3. Relation to GitHub CRM_system

Verdict: **different deployment/codebase, with overlapping CRM product concepts**.

The compared worktree is `flycited2-dotcom/CRM_system` commit
`6aa76d3389ff9499a87d262082a7217a45fd759d`.

Strong differences:

- The public mock uses static `/app/*.html` and `/assets/*` paths.
- The GitHub version uses Next.js 16, React 19, NestJS 11, Prisma 6, PostgreSQL,
  Redis, JWT authentication, and `/api/*` routes.
- The GitHub root redirects to `/login`; the public mock redirects to
  `/app/dashboard-owner.html`.
- The GitHub health contract is `/api/health` returning
  `{ status: "ok", service: "crm-api" }`; the current public host returns 404.
- The current Git commit contains zero tracked HTML files, and the fetched Git
  history has no entries for `dashboard-owner.html`, `mock-data.js`,
  `assets/js/shell.js`, or `app/clients/list.html`.

Functional comparison:

| Area | Public 213 mock | GitHub commit 6aa76d3 |
| --- | --- | --- |
| Authentication | Role stored locally; no credential check | Real JWT login/refresh/logout and RBAC |
| Clients | Rich mock list/card | Real list/create/card, CRUD, contacts, comments, files, history |
| Leads | Mock list and kanban | Real list/create/card, assign, close, history, convert to client |
| Employees | Mock list/card | Real users API; one users screen |
| Deals | Four mock screens | Not implemented; conversion remains a placeholder |
| Tasks | Five mock screens | Not implemented |
| Offers | Two mock screens | Not implemented |
| Tenders | Three mock screens | Not implemented |
| Reports/settings | Mock presentation screens | No matching frontend modules yet |
| Lead webhooks | Display-only endpoint strings | Explicitly excluded from the current stage |

An important contradiction must be preserved: repository handoff documentation
records that the real Next/Nest/PostgreSQL application was previously deployed and
smoke-tested on `213.109.202.45`. The current HTTP surface therefore appears to
have been replaced or rerouted later. HTTP alone cannot establish whether its old
database, uploads, containers, or checkout still remain on the server.

## 4. Required work before retiring 213

Do not retire the server based only on this HTTP audit.

Mandatory server-side inventory and backup:

1. Record running/stopped containers, Compose projects, services, listening ports,
   source checkouts, Git commits/status, cron jobs, and nginx virtual hosts.
2. Archive the static web root byte-for-byte. It is not present in the compared
   GitHub history and may be useful as the full visual/functional prototype.
3. If PostgreSQL or the `crm_postgres_data` volume exists, create a logical
   `pg_dump`, verify that it restores, and record table/row counts without exposing
   personal data.
4. Archive the `crm_uploads` volume, `.env.production`, Compose files, nginx config,
   migration state, and any uncommitted source changes. Secrets must stay outside
   GitHub.
5. Redis data is normally rebuildable, but record and back it up if it contains
   queues or state that the application treats as durable.

Recommended redeployment model:

- Deploy source cleanly from GitHub commit `6aa76d3` (or a later approved commit).
- Restore database and uploaded files separately; do not treat a Git clone as a
  data backup.
- Verify `/api/health`, real login, users/clients/leads counts, file access, and a
  controlled CRUD smoke test on the target.
- Keep `213.109.202.45` available until backup hashes, restore verification, and
  target runtime checks are complete.
