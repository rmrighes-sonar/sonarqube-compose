# sonarqube-compose

Local SonarQube stack for demos/testing, run via Docker Compose.

## Overview

`compose.yaml` defines a core stack plus two opt-in profiles:

- **Core** (always started): `db` (Postgres) → `sonarqube`, connected over
  the default Compose network. Both are only bound to `127.0.0.1`.
- **`monitoring` profile**: `prometheus` scrapes SonarQube's
  `/api/monitoring/metrics` endpoint (authenticated via a passcode) for
  server/process health, and `sonarqube-exporter` (a separate service,
  published from the sibling
  [`sonarqube-exporter`](https://github.com/rmrighes-sonar/sonarqube-exporter)
  repo) for project/portfolio quality data that endpoint doesn't cover.
  `grafana` visualizes both through two pre-provisioned dashboards — see
  [Dashboards](#dashboards) below.
- **`share` profile**: `ngrok` tunnels the local SonarQube instance to a
  fixed public hostname, for sharing access outside your machine.

All services declare healthchecks, and dependent services wait on
`service_healthy` before starting (e.g. `prometheus`/`ngrok` wait for
SonarQube to actually be serving requests, not just for the container to
have started).

## Setup

1. Copy `.env.example` to `.env` and fill in real values:
   ```bash
   cp .env.example .env
   ```
   `.env` is gitignored and must never be committed.
2. Review [Prerequisites](#prerequisites) below.
3. Start the stack:
   ```bash
   docker compose up -d                          # core: SonarQube + Postgres
   docker compose --profile monitoring up -d     # + Prometheus + Grafana
   docker compose --profile share up -d          # + ngrok tunnel
   ```
   Profiles can be combined, e.g. `docker compose --profile monitoring --profile share up -d`.

## Ports & credentials

| Service    | URL                          | Credentials                                             |
|------------|-------------------------------|----------------------------------------------------------|
| SonarQube  | http://localhost:9000        | default admin/admin on first login                       |
| Prometheus | http://localhost:9090        | none (local only)                                         |
| Grafana    | http://localhost:3000        | `admin` / `GRAFANA_ADMIN_PASSWORD` (from `.env`)          |
| sonarqube-exporter | http://localhost:9091/metrics | none (local only) — raw Prometheus exposition, for debugging |
| ngrok      | http://localhost:4040 (inspector) / `NGROK_URL` (public) | n/a |

## Dashboards

Grafana (`monitoring` profile) is pre-provisioned with two dashboards in a
"SonarQube" folder:

- **SonarQube Server Health** (`grafana/dashboards/sonarqube-health.json`) —
  availability of the Web/Compute Engine/Elasticsearch processes, license
  usage, Elasticsearch disk health, Compute Engine task throughput/duration,
  Web API v1/v2 request rate and p95 latency, database query rate/latency,
  external integration health, and connected SonarLint clients. Backed
  entirely by the existing `Prometheus` datasource — no extra setup needed
  beyond the `monitoring` profile.

  **Troubleshooting "Could not find plugin definition for data source" /
  panels showing the Prometheus datasource as missing:** Grafana's
  background plugin installer re-checks every core-bundled plugin
  (including `prometheus`) on every startup regardless of what's set in
  `GF_PLUGINS_PREINSTALL`, and by default (`preinstall_auto_update`)
  deletes the currently-working bundled binary *before* fetching its
  replacement from `storage.googleapis.com`. On networks that
  intercept/proxy that host, the fetch fails, leaving the plugin
  uninstalled until a startup where the fetch happens to succeed — so
  every `docker compose down && up` could permanently break this
  dashboard. `compose.yaml` sets
  `GF_PLUGINS_PREINSTALL_AUTO_UPDATE=false` to stop Grafana from touching
  an already-installed bundled plugin; it still installs one fresh if
  truly missing. If you're recovering from this failure on an existing
  `grafana_data` volume (the bundled plugin directory lives in the
  image, not that volume, so a plain restart won't restore it), force a
  fresh container so it's re-extracted from the image:
  `docker compose up -d --force-recreate grafana`.

- **SonarQube Usage — Projects & Portfolios**
  (`grafana/dashboards/sonarqube-usage.json`) — a usage/quality snapshot
  for selected projects: KPI strip (failing gates, LoC, average coverage,
  vulnerabilities, bugs), analysis recency, quality-gate distribution,
  ranked issue charts, LoC by project, a formatted measures table (overall
  and new-code metrics, A–E ratings, links into SonarQube), and separate
  coverage/duplication vs LoC trend charts. Portfolios (Enterprise/
  Governance) and last-analysis-status are collapsed by default.

  Backed entirely by the `Prometheus` datasource — the same as the Health
  dashboard, and the same pattern for every panel in this dashboard now.
  SonarQube doesn't expose this project/portfolio data via its own
  `/api/monitoring/metrics` endpoint, so a separate service,
  **`sonarqube-exporter`** (source:
  [`rmrighes-sonar/sonarqube-exporter`](https://github.com/rmrighes-sonar/sonarqube-exporter),
  published as a private image on `ghcr.io`), queries SonarQube's Web API on
  its own 60s schedule and re-exposes the results as ordinary
  `sonarqube_project_*`/`sonarqube_portfolio_*` Prometheus metrics —
  Grafana never calls SonarQube's Web API directly. See that repo's
  `README.md` for the full metric contract.

  Trend panels use the single-select **Project (history)** variable
  together with the dashboard's time range (default last 90 days) — this
  is real Prometheus history retained since the exporter started being
  scraped, not a call to SonarQube's `search_history` API. KPI/table/bar
  panels are an *instant* Prometheus query (current state), independent of
  the time range.

  **Project**, **Project (history)**, and **Portfolio** are real
  `query`-type variables using `label_values(sonarqube_project_info,
  project)` / `label_values(sonarqube_portfolio_info, portfolio)` — dynamic
  and auto-discovering (add/remove a SonarQube project and it appears or
  disappears here on the next scrape, no dashboard edits needed), and
  "All" works correctly. This directly replaces the static `custom`-type
  variables an earlier version of this dashboard needed as a workaround for
  the Infinity datasource's broken "All"-expansion behavior against this
  same API — Prometheus's own variable engine doesn't have that problem.

  To populate this dashboard:
  1. In SonarQube, generate a token: **My Account &gt; Security &gt; Generate
     Tokens** (or use a dedicated read-only service account). The token's
     user needs Browse permission on the projects/portfolios you want
     charted.
  2. Set `SONARQUBE_API_TOKEN` in `.env` to that token (now consumed by
     `sonarqube-exporter`, not by Grafana directly).
  3. **One-time per machine**: log Docker in to GHCR so it can pull the
     private exporter image (`sonarqube-exporter` is private, matching this
     repo's own visibility):
     ```bash
     gh auth token | docker login ghcr.io -u <your-github-username> --password-stdin
     ```
     (Requires the [`gh` CLI](https://cli.github.com/) authenticated with at
     least `read:packages` scope, and to be a collaborator on that repo. Any
     [personal access token](https://github.com/settings/tokens) with
     `read:packages` works the same way in place of `gh auth token`.)
  4. `docker compose --profile monitoring up -d` (or restart if already
     running): `docker compose up -d sonarqube-exporter prometheus grafana`.

  Known limitations, inherited from `sonarqube-exporter`: the exporter's
  own `/api/projects/search`, `/api/components/search`, and
  `/api/measures/search` calls rely on SonarQube's internal/undocumented
  measures-search endpoint (same caveat that applied when this dashboard
  called it directly) — see that repo's README for the stable fallback and
  full trade-offs (no history backfill from before the exporter existed;
  the old raw "recent analyses" event list is now a last-status-per-project
  gauge instead of a log with exact timestamps/errors).

  **Troubleshooting an empty usage dashboard:**
  - Check `sonarqube_exporter_up` in Prometheus/Explore — `0` means the
    exporter's last scrape of SonarQube's Web API failed; check
    `docker compose logs sonarqube-exporter` for the specific API error
    (commonly an invalid/expired `SONARQUBE_API_TOKEN`, or the token's user
    lacking Browse permission).
  - If `sonarqube-exporter` won't even start (image pull error), confirm
    step 3 above — `docker compose logs sonarqube-exporter` will show
    `unauthorized`/`denied` if the machine isn't logged in to `ghcr.io`.
  - Check Prometheus's Targets page (`http://localhost:9090/targets`) for
    the `sonarqube-projects` job's health and `lastError`.

## GitHub Integration

This SonarQube instance can be bound to GitHub (personal account
`rmrighes-sonar`) via a GitHub App, enabling repository import, branch/PR
analysis, and pull request decoration (quality gate status posted as a
GitHub check/comment). CI scanning workflows in the integrated repos
(`sonarqube-compose`, `sonarqube-exporter`) push analysis results to this
server over the `share` profile's `ngrok` tunnel, since GitHub-hosted
Actions runners can't reach `localhost` or your LAN directly.

**Why `ngrok` is required here:** two things need the local SonarQube
instance to be publicly reachable —
- GitHub's "Install & Authorize" redirect during GitHub App creation (a
  browser round-trip back to SonarQube).
- GitHub-hosted Actions runners calling `SONAR_HOST_URL` to push analysis
  results.

PR decoration itself (SonarQube posting a check/comment) is an *outbound*
call from SonarQube to GitHub's API, so it doesn't need any extra exposure
beyond the above.

### One-time setup (manual, in a browser — not scriptable)

1. Start the tunnel: `docker compose --profile share up -d`, and confirm
   `NGROK_URL` (from `.env`) is live.
2. In SonarQube: **Administration > Configuration > General Settings >
   General**, set **Server base URL** to your `NGROK_URL`. Required, or the
   GitHub App redirect and PR-decoration links break.
3. In SonarQube: **Administration > Configuration > General Settings >
   DevOps Platform Integrations > GitHub tab > Create app for me**. This
   redirects to GitHub, generates a manifest-based GitHub App under your
   `rmrighes-sonar` account, and on **Install & Authorize** saves the App
   ID / Client ID / Client Secret / Private Key back into a new GitHub
   Configuration record automatically.
   - When prompted where to install the app, choose **All repositories**
     so future repos are covered automatically, not just the current two.
4. Back in SonarQube: **Projects > Create Project > GitHub**, select the
   new configuration, and import `rmrighes-sonar/sonarqube-compose` and
   `rmrighes-sonar/sonarqube-exporter`. This binds each project to its
   GitHub repo (enables branch/PR analysis + decoration once a scan runs).
5. Generate a project analysis token per repo: **My Account > Security >
   Generate Tokens** (type: Project Analysis Token) — or reuse a single
   token across both repos if you prefer less setup.
6. Push the CI connection settings into each repo (no browser needed):
   ```bash
   gh secret set SONAR_TOKEN -R rmrighes-sonar/sonarqube-exporter -b "<token>"
   gh variable set SONAR_HOST_URL -R rmrighes-sonar/sonarqube-exporter -b "<NGROK_URL>"
   gh secret set SONAR_TOKEN -R rmrighes-sonar/sonarqube-compose -b "<token>"
   gh variable set SONAR_HOST_URL -R rmrighes-sonar/sonarqube-compose -b "<NGROK_URL>"
   ```

### CI scanning

Both repos have a `sonar-project.properties` file and a GitHub Actions job
(using `SonarSource/sonarqube-scan-action`) that scans on `push` and
`pull_request` and pushes results to `SONAR_HOST_URL`. See each repo's
`.github/workflows/` for the exact job.

**Caveats:**
- CI scans only succeed while the local Docker stack *and* the `ngrok`
  tunnel are both running — GitHub-hosted runners can't reach SonarQube
  otherwise.
- `NGROK_URL` and the SonarQube Server base URL must stay in sync: if the
  ngrok URL ever changes (new plan/session), update both the SonarQube
  Server base URL setting and the `SONAR_HOST_URL` repo variables.

## Prerequisites

SonarQube bundles an embedded Elasticsearch instance, which requires the
host's `vm.max_map_count` to be at least `262144`. If this isn't set,
SonarQube will fail to start (often with an Elasticsearch bootstrap error in
its logs).

- **Linux:**
  ```bash
  sudo sysctl -w vm.max_map_count=262144
  ```
  To persist across reboots, add `vm.max_map_count=262144` to
  `/etc/sysctl.conf` (or a file under `/etc/sysctl.d/`).

- **macOS / Windows with Docker Desktop:** the Linux kernel actually backing
  your containers runs inside Docker Desktop's VM, so the sysctl above must
  be applied to that VM, not your host OS. Run:
  ```bash
  docker run --rm --privileged --pid=host justincormack/nsenter1 sysctl -w vm.max_map_count=262144
  ```
  This needs to be re-applied whenever the Docker Desktop VM restarts (e.g.
  after a reboot or Docker Desktop restart).

- **Memory/CPU:** in Docker Desktop, allocate at least 4 GB RAM and 2 CPUs
  to the Docker VM (Settings → Resources) — SonarQube plus its Elasticsearch
  index needs headroom beyond the container's own `deploy.resources` limits
  configured in `compose.yaml`.

## Image policy

This stack intentionally tracks the latest release on every image
(SonarQube's rolling `enterprise` tag, and `latest` for Prometheus/Grafana)
for simplicity in local demos, rather than pinning to immutable versions.
Trade-off: `docker compose pull` can introduce breaking changes between
runs, so only re-pull deliberately, and expect to occasionally re-validate
the stack afterwards.

## Secrets handling

- Real secrets live only in `.env` (gitignored); `.env.example` documents
  every key with safe placeholders for onboarding.
- `SONAR_SYSTEM_PASSCODE` authenticates Prometheus's scrape of SonarQube's
  monitoring endpoint. Rather than duplicating that value as plaintext
  inside the git-tracked `prometheus/prometheus.yml`, it's passed via a
  Compose secret sourced directly from the env var:
  ```yaml
  secrets:
    sonar_system_passcode:
      environment: SONAR_SYSTEM_PASSCODE
  ```
  Prometheus reads it from the resulting `/run/secrets/sonar_system_passcode`
  file via `authorization.credentials_file`, so `.env` remains the single
  source of truth and no secret value is ever written into a tracked file.

## Backup & Restore

State lives in Docker named volumes: `postgres_data` (the database, the
source of truth for SonarQube's configuration/analysis history) and
`sonarqube_data`/`sonarqube_extensions` (Elasticsearch index + installed
plugins, both rebuildable/reinstallable but convenient to preserve).

- **Back up:**
  ```bash
  ./scripts/backup.sh
  ```
  Writes a `pg_dump` of the database plus tarballs of the SonarQube data and
  extensions volumes into `backups/<timestamp>/` (gitignored — copy these
  elsewhere for real safekeeping, e.g. off-host storage).

- **Restore:**
  ```bash
  ./scripts/restore.sh backups/<timestamp>
  ```
  Prompts for confirmation, restores the database, then stops `sonarqube`
  to safely overwrite its data/extensions volumes before starting it back
  up.
