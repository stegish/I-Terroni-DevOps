# MiniTwit monitoring stack

Prometheus + Grafana + Loki, fully provisioned from files in this repo. Reach
the UIs through an SSH tunnel:

```sh
ssh -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 root@<manager-droplet>
# Grafana → http://localhost:3000   (admin / $GF_SECURITY_ADMIN_PASSWORD)
# Prom    → http://localhost:9090
```

## What runs where

| Service          | Mode        | Where      | Scraped via                          |
| ---------------- | ----------- | ---------- | ------------------------------------ |
| `prometheus`     | replicas: 1 | manager    | self-scrape                          |
| `grafana`        | replicas: 1 | manager    | —                                    |
| `loki`           | replicas: 1 | manager    | Grafana datasource                   |
| `promtail`       | global      | every node | pushes to Loki                       |
| `node-exporter`  | global      | every node | DNS SD `tasks.node-exporter:9100`    |
| `cadvisor`       | global      | every node | DNS SD `tasks.cadvisor:8080`         |
| `mysqld-exporter`| replicas: 1 | manager    | static `mysqld-exporter:9104`        |
| `minitwit`       | replicas: 3 | workers    | DNS SD `tasks.minitwit:5000`         |

`tasks.<service>` is Swarm-internal DNS that returns *every* task IP for a
service — so each app replica is scraped individually.

## Required env vars (in `.env`)

```
GF_SECURITY_ADMIN_PASSWORD=...
MYSQLD_EXPORTER_HOST=db-mysql-...ondigitalocean.com:25060
MYSQLD_EXPORTER_USER=exporter
MYSQLD_EXPORTER_PASSWORD=...
```

The exporter user should be dedicated and read-only. On the managed DB:

```sql
CREATE USER 'exporter'@'%' IDENTIFIED BY '...';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
GRANT SELECT ON performance_schema.* TO 'exporter'@'%';
```

## Dashboards

Six domain dashboards, one question each. They're loaded automatically from
`grafana/dashboards/` (provisioning config in `grafana/provisioning/`).

| File                       | UID                          | Answers                                       |
| -------------------------- | ---------------------------- | --------------------------------------------- |
| `01-business.json`         | `minitwit-business`          | How is the product doing?                     |
| `02-api-http.json`         | `minitwit-api-http`          | Are the endpoints fast and error-free?        |
| `03-system-health.json`    | `minitwit-system-health`     | Is the platform up?                           |
| `04-infrastructure.json`   | `minitwit-infrastructure`    | Are the droplets healthy (per-instance)?      |
| `05-database.json`         | `minitwit-database`          | Is MySQL healthy?                             |
| `06-logs.json`             | `minitwit-logs`              | What's going wrong and where?                 |

The legacy dashboards (`api.json`, `software.json`, `hardware.json`) are still
there during the transition and will be removed once the new boards are
verified in production.

### 01 — Business / Product

Source: app-exposed Prometheus gauges + HTTP route counters.

- KPI strip: `minitwit_total_users`, `minitwit_total_messages`, `minitwit_total_follows`, `minitwit_avg_followers`.
- Growth over time for the same gauges.
- Activity rates derived from `minitwit_http_requests_total` filtered by
  route (`register`, `add_message`, `api_user_msgs`, `follow_user`,
  `unfollow_user`, `login`, timeline routes).
- Engagement ratios: msgs/user, follows/user, timeline reads/min.

### 02 — API / HTTP

Source: `minitwit_http_requests_total`,
`minitwit_http_request_duration_seconds`, `minitwit_http_errors_total`. All
labelled by `method`, `route`, `status` (and `status_class` for errors).

- Top SLI strip: 5xx %, 4xx %, global p95, total req/s.
- Per-route traffic mix and status code distribution.
- p50 / p95 / p99 latency by route.
- Stacked error rate by route × status class.
- Top-10 tables: busiest routes, slowest p95 routes, error-rate routes.
- `$route` template variable lets you focus on one or many endpoints.

### 03 — System Health

Source: `up`, cAdvisor `container_start_time_seconds`,
`minitwit_http_errors_total`, legacy function counters.

- Replicas up, scrape targets healthy, recent 5xx count, restarts (1h).
- Scrape target inventory (UP/DOWN table) and up-state timeseries.
- Container restart bars and uptime table.
- 4xx vs 5xx stream.
- Collapsed "Refactoring candidates" row keeping the legacy
  `minitwit_fct_*_total` counters in view.

### 04 — Infrastructure

Source: node-exporter (per droplet) and cAdvisor (per container).

- `$instance` variable (multi-select) drives every panel.
- CPU %, Memory %, Disk usage % KPI strip per droplet.
- Normalised load average (load / CPU count).
- Memory used vs total bytes.
- Disk available + I/O utilisation.
- Network RX and TX.
- Per-container CPU and working-set memory (cAdvisor).

### 05 — Database

Source: mysqld-exporter + app-side `minitwit_db_query_duration_seconds`.

- KPIs: mysql up, active connections, queries/s, slow queries/s.
- Read vs write breakdown from `mysql_global_status_commands_total`.
- Connections used vs `max_connections`.
- App-side DB latency p50/p95/p99 (kept here, **removed** from the API
  dashboard once the new boards take over).
- InnoDB buffer pool hit ratio.
- Bytes sent/received.
- Top 20 tables by data + index size.

### 06 — Logs

Source: Loki. Every container is captured by Promtail (global mode) via the
Docker socket; the only label currently extracted is `container`.

- KPIs: total log rate, error rate, warning rate, active container count.
- Per-container coverage timeseries + presence table — explicit proof that
  every container is shipping logs.
- Top-10 containers by error count and stacked per-container error rate.
- Live log stream filtered by `$container` (multi) and `$severity` (regex).

## How to add a metric

1. Define the collector in [`metrics.py`](../metrics.py) (Counter / Gauge /
   Histogram from `prometheus_client`).
2. Use it from the app (the HTTP tween in
   [`minitwit_refactor.py`](../minitwit_refactor.py) already covers
   request-level metrics).
3. The `/metrics` endpoint ([`api.py`](../api.py)) refreshes business gauges
   on every scrape — extend `api_metrics()` if you add new gauges.
4. Add a panel to the relevant dashboard JSON. Don't click in the UI —
   dashboards are read-only at provisioning time and any UI edits are lost
   on restart.

## How to add an exporter

1. Add the service to [`../docker-compose.yml`](../docker-compose.yml). Use
   `mode: global` for node-local exporters, `replicas: 1` on the manager for
   single-target ones.
2. Add a scrape job to [`prometheus.yml`](prometheus.yml). For Swarm-internal
   services prefer DNS SD on `tasks.<service>`.
3. If the exporter needs credentials, source them from `.env` via
   `${VAR:?...must be set...}` — never hard-code.

## Quick sanity checks

```sh
# All scrape targets healthy?
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job:.labels.job, instance:.labels.instance, health:.health}'

# App metrics endpoint responds?
docker exec $(docker ps -qf name=minitwit | head -1) curl -s http://localhost:5000/metrics | head

# Loki receiving logs?
curl -s "http://localhost:3100/loki/api/v1/labels"
```
