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
  (`grafana/dashboards/sonarqube-usage.json`) — per-project quality gate
  status, bugs/vulnerabilities/code smells, coverage, duplication, lines of
  code, a portfolios overview (if any are configured — requires the
  Enterprise/Governance edition), recent Compute Engine analyses, and a
  coverage/duplication/size history chart for a single selected project.
  This data isn't available via Prometheus, so it's queried directly from
  SonarQube's Web API using Grafana's **Infinity** datasource plugin
  (`yesoreyeram-infinity-datasource`, installed automatically via
  `GF_PLUGINS_PREINSTALL`).

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
  stable fallback. The "Coverage / duplication / size history" panel only
  supports a single selected project, not "All" (SonarQube's
  `search_history` endpoint takes one component at a time).

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
