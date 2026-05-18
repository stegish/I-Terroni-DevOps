# Security Assessment & Hardening Report

This document is the security deliverable for the I-Terroni project. It follows the structure suggested in the lecture: a risk assessment (identification + analysis) followed by the concrete hardening steps that were applied to the system.

---

## 1. Risk Assessment

### 1.A Risk Identification

#### 1.A.1 Assets

| # | Asset | Where it lives | Why it matters |
| --- | --- | --- | --- |
| A1 | MiniTwit web/API application (Pyramid + gunicorn) | 3 replicas across the 2 worker droplets, image `michaelfant/minitwitimage:latest` | Public-facing service. Compromise = service downtime, defacement, or pivot point into the rest of the stack. |
| A2 | MySQL 8 managed database (DigitalOcean) | Outside the swarm, reached via `DATABASE_URL` | Holds all user data: usernames, e-mails, password hashes, messages, follow graph. The crown jewels. |
| A3 | Observability stack: Prometheus, Grafana, Loki, Promtail | Manager droplet only | Holds operational telemetry (metrics, logs). Logs may contain user input echoes. Grafana is a known credential-leak vector. |
| A4 | Docker Hub image `michaelfant/minitwitimage` | Public registry | If an attacker gets push access, every redeploy ships their code into production. |
| A5 | DigitalOcean droplets (2 workers + 1 manager) | DigitalOcean | The hosts themselves. Root on a host, game over for everything running on it. |
| A6 | CI/CD pipeline (GitHub Actions) | GitHub | Has access to: `DOCKER_PASSWORD`, `SSH_KEY`, `DROPLET_IP`, `DATABASE_URL`, `SONAR_TOKEN`, `CODACY_PROJECT_TOKEN`. Compromise = full production compromise. |
| A7 | Source repository on GitHub | GitHub | Code, infrastructure-as-code, workflow definitions. Anyone with write access can ship a backdoor. |
| A8 | Secrets in `.env` (local) | Developer machines + droplet `/vagrant/.env` | Contains the production `DATABASE_URL`. |

#### 1.A.2 Threat sources & risk scenarios

Mapped against the OWASP Top 10 (2021) categories the lecture references.

| # | Risk scenario | OWASP cat. | Asset(s) hit |
| --- | --- | --- | --- |
| R1 | **SQL injection** via the simulator API or HTML form fields lets the attacker dump the user table, including password hashes. | A03 Injection | A1, A2 |
| R2 | **XSS** in the public timeline, an attacker posts a message containing `<script>` that runs in every visitor's browser, hijacking sessions. | A03 Injection | A1 |
| R3 | **Hard-coded simulator credentials** (`Basic c2ltdWxhdG9yOnN1cGVyX3NhZmUh` = `simulator:super_safe!`, in `api.py`) leak via the public Docker image and grant full simulator-API access. | A07 Auth Failures | A1, A2 |
| R4 | **Default Pyramid `SECRET_KEY = "development key"`** if `SECRET_KEY` env var isn't set, signed session cookies become forgeable. | A07 Auth Failures | A1 |
| R5 | **ElasticSearch-style port-mapping leak**: Docker bypasses `ufw` and exposes any `-p X:Y` port directly to the internet. Today this affects ports 8080 (app), 9090 (Prometheus), 3000 (Grafana, default `admin/admin`), 3100 (Loki), 9100 (node-exporter). | A05 Misconfiguration | A1, A3, A5 |
| R6 | **Unencrypted HTTP traffic**: app served on port 8080 with no TLS. Credentials, session cookies, and `Authorization` headers are readable on any hop. | A02 Cryptographic Failures | A1, A2 |
| R7 | **Containers run as root** (no `USER` directive in any Dockerfile). A code-execution bug becomes container-root, which on a kernel CVE (e.g. runc / Dirty Pipe) becomes host-root. | A05 Misconfiguration | A1, A5 |
| R8 | **Outdated base images** (`python:3.9-slim`, 3.9 is in security-fix-only mode, scheduled EOL). Known CVEs accumulate over time. | A06 Vulnerable Components | A1 |
| R9 | **Vulnerable Python dependencies** none of `pyramid`, `gunicorn`, `werkzeug`, `pymysql`, `sqlalchemy` are pinned with version checks; a transitive CVE goes unnoticed. | A06 Vulnerable Components | A1 |
| R10 | **Supply-chain compromise of GitHub Actions** third-party action repointed to a malicious commit (cf. the axios March 2026 hijack). Workflow secrets exfiltrated. | A06 Vulnerable Components | A4, A6 |
| R11 | **Docker Hub credentials leak** image registry is public; with push creds, attacker publishes a backdoored `minitwitimage:latest` and the next `deploy.sh` ships it. | A07 Auth Failures | A4 |
| R12 | **SSH key compromise** of the deploy key stored as `SSH_KEY` GitHub secret direct `root@droplet` shell. | A07 Auth Failures | A5, A6 |
| R13 | **No authentication on Grafana / Prometheus** beyond the default `admin/admin` Grafana password (set explicitly in `docker-compose.yml`). Combined with R5, public Grafana with default creds. | A05 Misconfiguration | A3 |
| R14 | **Insufficient logging & monitoring** no auditing of failed logins, no alert on anomalous request rates, no SIEM. Breach goes unnoticed for the IBM-study average of 6 months. | A09 Logging Failures | A1, A3 |
| R15 | **No backup of the production MySQL** beyond what DO Managed offers by default; a destructive injection or accidental migration loses user data. | A05 Misconfiguration | A2 |
| R16 | **Public ElasticSearch-style ransom** manager droplet has Loki on port 3100 reachable from the internet (R5). Same playbook as the lecture's anecdote. | A05 Misconfiguration | A3 |

### 1.B Risk Analysis

#### Likelihood and Impact scales used

Following the Security Risk Management BoK levels referenced in the lecture:

- **Likelihood:** Rare / Unlikely / Possible / Likely / Certain
- **Impact:** Insignificant / Negligible / Marginal / Critical / Catastrophic

#### Per-scenario rating

| # | Risk | Likelihood | Impact | Priority |
| --- | --- | --- | --- | --- |
| R1 | SQL injection | Unlikely (SQLAlchemy ORM is parameterised) | Catastrophic (full DB) | Medium |
| R2 | XSS in timeline | Possible (template auto-escapes, but check needed) | Critical | Medium |
| R3 | Hard-coded simulator creds | Certain (already in public image) | Critical | **High** |
| R4 | Default `SECRET_KEY` | Possible (depends on deploy-time env) | Critical (session forgery) | **High** |
| R5 | Docker bypasses `ufw` | Certain (this is the current state) | Catastrophic (R16 follows directly) | **High** |
| R6 | No TLS | Certain | Critical (creds in clear) | **High** |
| R7 | Containers run as root | Certain | Critical (depends on kernel CVE) | Medium |
| R8 | Outdated base image (Py 3.9) | Likely (drift over time) | Critical | **High** |
| R9 | Vulnerable dependency | Possible | Critical | Medium |
| R10 | Compromised GH Action | Unlikely | Catastrophic | Medium |
| R11 | Docker Hub creds leak | Unlikely (2FA enforced) | Catastrophic | Medium |
| R12 | SSH key leak | Unlikely | Catastrophic | Medium |
| R13 | Default Grafana creds | Certain | Critical | **High** |
| R14 | No log monitoring | Likely | Critical (delayed detection) | **High** |
| R15 | No tested backup | Possible | Catastrophic | Medium |
| R16 | Loki/ES-style ransom | Possible | Critical | **High** |

#### Risk matrix

```
                       IMPACT →
                Insig. Negl. Marg. Crit.        Catastr.
LIKELIHOOD ↓
Certain                              R3 R6 R13   R5
Likely                               R8 R14
Possible                       R2    R4 R9 R16   R15
Unlikely                             R7           R1 R10 R11 R12
Rare
```

The top-right (Certain × Catastrophic / Critical) cluster is what we address first.

#### What we do about each mitigation plan

| # | Mitigation | Implemented in this branch |
| --- | --- | --- |
| R3 | Move the simulator credential out of the image, into an env var; rotate the secret. | **Yes `api.py`: reads `SIMULATOR_BASIC_AUTH` env var; hard-coded token removed.** |
| R4 | Make `SECRET_KEY` mandatory at boot; remove the `"development key"` fallback. | **Yes `minitwit_refactor.py`: `os.environ["SECRET_KEY"]` (no fallback); app crashes on startup if unset.** |
| R5 | Bind every internal port to `127.0.0.1` in `docker-compose.yml`; install and enable `ufw`; expose only 22 / 80 / 443 publicly. | **Yes, §2.A.** |
| R6 | Add Nginx reverse proxy + Let's Encrypt TLS certificate; redirect HTTP → HTTPS. | **Yes, §2.B (config + script).** |
| R7 | Add a non-root `USER` to every Dockerfile. | **Yes, §2.C.** |
| R8 | Bump `python:3.9-slim` → `python:3.12-slim`. | **Yes, §2.C.** |
| R9 | Add a Trivy scan of the built image in CI; fail on HIGH/CRITICAL. | **Yes §2.D.** |
| R10 | Pin third-party actions to commit SHA (already done). Keep Codacy/Sonar SHA pins. | Pre-existing. |
| R11 / R12 | Enforce 2FA on Docker Hub & GitHub. | Operational. |
| R13 | Move the Grafana admin password to a Docker secret / `.env`; make it non-default. | **Yes, `docker-compose.yml`: uses `${GF_SECURITY_ADMIN_PASSWORD:?...}` (deploy fails if unset); `:-admin` default removed.** |
| R14 | Add Semgrep SAST in CI (shift-left); centralise logs in Loki (already done); add alert rules. | **Yes, §2.D for SAST.** |
| R15 | Use DigitalOcean Managed MySQL automated backups. | Operational. |
| R16 | Same as R5 (firewall) + auth on every internal service. | Covered by §2.A. |

---

## 2. Hardening Applied in This Branch

### 2.A Firewall

Two changes were made:

1. **`Vagrantfile`** provisioning now installs and configures `ufw` so the host firewall denies everything by default and only opens 22 (SSH), 80 (HTTP), 443 (HTTPS).
2. **`docker-compose.yml`** internal-only services (Prometheus, Grafana, Loki, node-exporter) now bind to `127.0.0.1:<port>` instead of `0.0.0.0:<port>`. The MiniTwit app port `8080` is also localhost-only because Nginx proxies into the swarm overlay network.

**Why both.** Docker rewrites `iptables` directly and bypasses `ufw`, so on its own, `ufw allow 22/80/443` does **not** close the Grafana / Prometheus ports that `-p` opens. Binding to `127.0.0.1` ensures the kernel never accepts the connection from outside, which is the recommended mitigation when you don't want to disable `iptables` integration in `/etc/docker/daemon.json`. The two layers are intentional defense-in-depth ("never rely on a single security mechanism").


### 2.B TLS

A new `nginx` service was added to `docker-compose.yml` and listens on 80 + 443 on the manager. It terminates TLS and proxies to the `minitwit` swarm service over the overlay network on port 5000.

The script issues a Let's Encrypt cert via certbot's standalone mode, drops the renewal hook into cron, and patches the Nginx config with the correct `server_name`. Renewal is automatic (90-day certs).

### 2.C Container Hardening

| Dockerfile | Before | After |
| --- | --- | --- |
| `Dockerfile-minitwit` | `python:3.9-slim`, runs as root | `python:3.12-slim`, dedicated `appuser` (UID 10001), `USER appuser` before `CMD` |
| `Dockerfile-minitwit-tests` | `python:3.9-slim`, runs as root | `python:3.12-slim`, `appuser`, `USER appuser` |

> The previous `Dockerfile-flagtool` (Ubuntu base + `gcc` + `libsqlite3` to build the legacy C admin tool) was hardened as part of this work, then removed entirely when the flag tool was rewritten as a Python script (`flag_tool.py`) that ships inside the main image. Removing it eliminated one base-image attack surface and one Docker Hub artifact (`michaelfant/flagtoolimage`).

A `.dockerignore` was also added to keep `.env`, `.git/`, the SQLite test DB, and the `out/` folder out of every image, both for security and image size.

Image-vulnerability scanning is wired into CI (next section), so regressions are caught on every push.

### 2.D CI/CD Security Gates (shift-left)

includes two gates:

1. **Semgrep** (SAST) runs in the `static-analysis` job, before the test step. Uses the `p/security-audit`, `p/owasp-top-ten`, and `p/python` rule packs. Fails the job on findings of severity ≥ ERROR.
2. **Trivy** (image vulnerability scan) runs in a new `security-scan` job that depends on `test` and gates `build-and-deploy`. Scans the locally-built `minitwitimage:ci` for OS-package and Python-dependency CVEs. Fails on `HIGH`/`CRITICAL` severity.

Job ordering:

```
static-analysis (ruff, codespell, mypy, hadolint, shellcheck, semgrep)
      ↓
test (integration + API + UI/E2E with MySQL + Selenium)
      ↓
security-scan (trivy on the built image)
      ↓
build-and-deploy (push to Docker Hub + ssh deploy)
```

Result: a build with a security finding above the threshold cannot be pushed to Docker Hub or deployed

The existing `code-quality.yml` (SonarCloud + Codacy) is left untouched and continues to run in parallel.

---


## 4. References

- OWASP Top 10 (2021): https://owasp.org/Top10/
- Docker / UFW interaction: https://docs.docker.com/network/iptables/
- runc CVE-2024-21626 ("Leaky Vessels"): https://nvd.nist.gov/vuln/detail/CVE-2024-21626
