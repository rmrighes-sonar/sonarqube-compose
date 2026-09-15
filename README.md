# sonarqube-compose

Local SonarQube stack for demos/testing, run via Docker Compose.

## Overview

`compose.yaml` defines a core stack plus two opt-in profiles:

- **Core** (always started): `db` (Postgres) → `sonarqube`, connected over
  the default Compose network. Both are only bound to `127.0.0.1`.
- **`monitoring` profile**: `prometheus` scrapes SonarQube's
  `/api/monitoring/metrics` endpoint (authenticated via a passcode), and
  `grafana` visualizes it through two pre-provisioned dashboards — see
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

- **SonarQube Usage — Projects & Portfolios**
  (`grafana/dashboards/sonarqube-usage.json`) — a usage/quality snapshot
  for selected projects: KPI strip (failing gates, LoC, average coverage,
  vulnerabilities, bugs), analysis recency, quality-gate distribution,
  ranked issue charts, LoC by project, a formatted measures table (overall
  and new-code metrics, A–E ratings, links into SonarQube), and separate
  coverage/duplication vs LoC trend charts. Portfolios (Enterprise/
  Governance) and recent Compute Engine REPORT tasks are collapsed by
  default. This data isn't available via Prometheus, so it's queried
  directly from SonarQube's Web API using Grafana's **Infinity** datasource
  plugin (`yesoreyeram-infinity-datasource`, installed automatically via
  `GF_PLUGINS_PREINSTALL`). Snapshot panels ignore the time picker; trend
  panels use it together with the single-select **Project (history)**
  variable. The dashboard refreshes every 5 minutes.

  To populate this dashboard:
  1. In SonarQube, generate a token: **My Account &gt; Security &gt; Generate
     Tokens** (or use a dedicated read-only service account). The token's
     user needs Browse permission on the projects/portfolios you want
     charted.
  2. Set `SONARQUBE_API_TOKEN` in `.env` to that token.
  3. Restart Grafana: `docker compose up -d grafana`.

  Known limitations: the "Projects overview" and "Portfolios overview"
  tables rely on SonarQube's internal/undocumented `GET
  /api/measures/search` endpoint (used by the SonarQube UI itself), which
  could change on a future SonarQube upgrade — if it breaks, the documented
  `GET /api/measures/component` endpoint (one call per project) is the
  stable fallback. Overall measures and new-code measures are two search
  calls (new-code values live under `period.value`, not `value`) pivoted
  in Grafana. Trend panels use **Project (history)** because
  `search_history` accepts one component at a time; pick that project and
  the dashboard time range (default last 90 days). KPI / table / bar
  panels are a live snapshot and do not honor the time picker. The
  Project/Portfolio dropdowns stay static — see below.

  **Project/Portfolio variable behavior:** the `Project`,
  `Project (history)`, and `Portfolio` variables are Grafana **`custom`**
  variables (a static, hardcoded comma-separated list of this instance's
  known keys), not `query` variables backed by a live Infinity datasource
  call. This was a deliberate, hard-won design decision after extensive
  debugging: a `query`-type variable against the Infinity datasource —
  with a live query, the built-in "All" pseudo-value, various `refresh`
  settings, and explicit static `current`/`options` overrides —
  repeatedly resolved the interpolated `projectKeys`/`portfolio` query
  parameter to an **empty string** in the actual outgoing HTTP request
  (confirmed repeatedly via the exact interpolated URLs captured from
  panel error responses), which SonarQube rejects with 400 ("Project keys
  must be provided"). This persisted across a genuinely fresh browser
  reload and several different variable configurations, and couldn't be
  fully root-caused without browser devtools access to Grafana's
  client-side variable engine. Manually selecting concrete values from a
  dropdown always interpolated correctly throughout the investigation, so
  the variables were switched to Grafana's simplest, static `custom`
  type, which has no datasource, no async query, and no "All"-expansion
  logic to go wrong.

  **If you add/remove SonarQube projects or portfolios**, the dropdown
  options won't automatically pick them up (this is the trade-off for
  reliability). Update them via **Dashboard settings → Variables →
  project / project_history / portfolio → Custom options**, or edit the
  `query`/`options`/`current` fields directly in
  `grafana/dashboards/sonarqube-usage.json`. Keep `project` and
  `project_history` in sync — they list the same keys.

  **Troubleshooting an empty usage dashboard:**
  - If every panel and the `Project`/`Portfolio` variables are empty, check
    whether the Infinity plugin actually installed:
    `docker compose logs grafana | grep backgroundinstaller`. On networks
    that intercept/proxy HTTPS to the Grafana plugin catalog
    (`storage.googleapis.com`), `GF_PLUGINS_PREINSTALL` can silently fail
    (Grafana itself still starts fine — the panels just show "Plugin not
    registered"). Workaround: download the matching
    `yesoreyeram-infinity-datasource` release zip from
    [GitHub releases](https://github.com/grafana/grafana-infinity-datasource/releases)
    on a machine with working access, extract it, and
    `docker cp` the extracted folder into the running container at
    `/var/lib/grafana/plugins/yesoreyeram-infinity-datasource` (this path is
    inside the persistent `grafana_data` volume, so it survives container
    restarts), then `docker compose restart grafana`.
  - All query/variable URLs in `sonarqube-usage.json` must be **absolute**
    (e.g. `http://sonarqube:9000/api/...`), not relative paths — Infinity
    checks the full URL's host against the datasource's `allowedHosts`
    security setting, and a relative path resolves to an empty host, which
    gets silently rejected.

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
