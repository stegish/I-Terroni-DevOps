# I-Terroni-DevOps

Welcome to the **I-Terroni-DevOps** repository for the ITU-MiniTwit application. This project is a micro-blogging platform built with Pyramid and deployed automatically using Docker and Vagrant on DigitalOcean.

## Why Pyramid over Flask/Bottle
We didn't use **Bottle + Jinja2** because it requires manually integrating two separate tools—a micro-framework and a template engine.

Flask improves on this but relies on global state (g object), making testing harder—you need to simulate Flask's application context.

We eventually chose Pyramid because:

*Explicit request object*: Attach DB/sessions directly to request.db, clean and testable

*Consistent structure*: Built-in Jinja2 (pyramid_jinja2), routing, and comprehensive docs

## Database Abstraction Layer (SQLAlchemy)

Without abstraction, our code was full with raw SQL queries written directly in functions: `SELECT * FROM user WHERE id=?`. This created chaos—changing databases meant rewriting everything, we risked SQL injection, and business logic got mixed up with SQL strings.

We fixed it with three distinct layers:

**db.py** handles only database connections. It's the single file that imports `sqlite3`.

**models.py** defines User and Message as Python objects. SQLAlchemy automatically translates them into tables and correct queries.

**App functions** now contain only business logic: they ask models for data using simple calls like `User.query.filter_by(id=1).first()`.


## Infrastructure & Deployment Documentation

We deploy our software using a Virtual Machine (Droplet) hosted on **DigitalOcean**, fully automated via **Vagrant** (Infrastructure as Code). 

### 1. Prerequisites
Before provisioning or deploying, ensure you have the following installed on your local machine (all the following command had been tested on Ubuntu 22.04):
* Vagrant
* The Vagrant DigitalOcean plugin. Install it by running:
  ```bash
  vagrant plugin install vagrant-digitalocean
  ```

### 2. Authentication & Secrets Setup (.env)

Every collaborator must create their own local .env file in the root of the cloned repository. Do not commit this file.

Create a .env file in the project root and add your DigitalOcean details:

```bash
export DO_TOKEN="your_personal_access_token_here"
export DO_SSH_KEY_NAME="your_key_name_on_digitalocean"
export DO_SSH_KEY_PATH="~/.ssh/id_ed25519" #path to your private key
```

### 3. Provisioning the Virtual Machine

To create the infrastructure from scratch, our Vagrantfile reads your secrets and spins up an ubuntu-22-04-x64 server in the fra1 region. It also automatically installs Docker and Docker Compose.

    Load your environment variables:

```bash
    source .env
```
    Tell Vagrant to create the server:

```bash
    vagrant up --provider=digital_ocean
```

### 4. Deploying the Application

Once the server is running, deploy the latest version of the application using our automated deployment script. This script syncs the project files to the /vagrant folder on the server, stops existing containers, and builds/starts the new ones.

    Ensure the script has execution permissions:
```bash
    chmod +x deploy_software.sh
```

    Run the deployment script:
```bash
    ./deploy_software.sh
```

Upon success, the script will output the public IP and the live URLs for the MiniTwit App (port 8080) and the Simulator API.
### 5. Testing the Deployment

To verify the deployment was successful, test the live endpoints against the public IP of the server. We use the provided Pytest suite configured for our public server address.

```bash
pytest minitwit_sim_api_test.py
```

If all tests pass, the application API is correctly tracking the latest variable and handling JSON payloads for registering, following, and tweeting!

### 6. Continuous Integration & Deployment (CI/CD)

We have transitioned from manual, local builds on the server to a fully automated CI/CD pipeline using **GitHub Actions** and **Docker Hub**. Vagrant serves as our Infrastructure as Code (IaC) tool for **initial provisioning** of the DigitalOcean Droplet. It automates VM creation (`vagrant up --provider=digital_ocean`), Docker installation, and SSH setup via API calls. Post-setup, GitHub Actions handles daily deploys directly via SSH (`deploy.sh`)

#### Architecture Updates
* **Decoupled Dockerfiles**: We split the original monolithic `Dockerfile` into three distinct images: `Dockerfile-minitwit`, `Dockerfile-flagtool`, and `Dockerfile-minitwit-tests`. Each image has a different purpose and lifecycle: `Dockerfile-minitwit` is the production image deployed to the server; `Dockerfile-minitwit-tests` runs exclusively in the CI pipeline and never reaches production, keeping test dependencies and debug code out of the final image; `Dockerfile-flagtool` is an administration utility used independently. This separation reduces image size and allows the CI pipeline to build and test in parallel, deploying only what is strictly necessary.

#### Why GitHub Actions?
Since our codebase is already hosted on GitHub and we deploy to DigitalOcean, GitHub Actions was the natural choice for our CD pipeline. It provides several key benefits for our workflow:
* **Easy Automation**: The entire pipeline is defined in a single YAML file. It automatically kicks off whenever a developer pushes to the `main` branch.
* **All-in-One Pipeline**: It seamlessly handles building the code, running our Pytest suite, pushing the compiled images to Docker Hub, and triggering the deployment script on our DigitalOcean Droplet via SSH.
* **Cost-Effective**: It requires no external Jenkins/Bamboo servers to maintain and is completely free for public repositories, making it the perfect fit for our project.

### 7. Database Migration (SQLite → MySQL)

We migrated the production database from SQLite to a **DigitalOcean Managed MySQL 8** instance. Each collaborator must add the `DATABASE_URL` to their local `.env` file using this template:
```
DATABASE_URL=mysql+pymysql://<username>:<password>@<host>:25060/<name_database>
```

The connection string is available in the DigitalOcean control panel under Databases → Connection Details.

#### Test vs Production database

The CI pipeline (GitHub Actions) uses **SQLite** for the test step, while production uses **MySQL**. This is an intentional and standard pattern for the following reasons:

* No cost: SQLite runs locally in the runner with no external service needed
* No whitelist issues: entirely in-process, no network involved
* Fast: no connection latency during tests

SQLAlchemy abstracts the difference between the two engines, so the same ORM models work on both without any code changes. The `DATABASE_URL` injected during tests is `sqlite:///tmp/minitwit.db`; the one injected at deploy time points to the DO MySQL instance via GitHub Secrets.

During the migration to MySQL, the existing SQLite data was not transferred to the new database. As a result, the production database restarted empty and will be filled with the new data of the simulator (16.03.2026).

### 8. Monitoring, Logging & Cluster Topology

We collect and visualize metrics with **Prometheus + Grafana** and logs with **Loki + Promtail**.

* **Hardware dashboard**: infrastructure-level metrics from `node-exporter` (CPU, memory, disk I/O, network traffic) on every Droplet.
* **Software dashboard**: application-level metrics instrumented in MiniTwit via `prometheus-client` (request counts, response times, endpoint activity).
* **Logs**: Promtail tails Docker container logs on each node and ships them to Loki, queryable from Grafana.

Both dashboards are provisioned automatically via the `monitoring/` directory mounted into the Grafana container, so they are available immediately after `docker stack deploy`.

#### Swarm topology (1 manager + 2 workers)

The cluster is intentionally split so the manager is reserved for the observability stack and never competes with the application for RAM/CPU:

| Service | Where it runs | Why |
| --- | --- | --- |
| `prometheus`, `grafana`, `loki` | **manager only** (`node.role == manager`) | Stateful — named volumes are bound to the manager so data survives redeploys. |
| `minitwit` (3 replicas), `flagtool` | **workers only** (`node.role == worker`) | Stateless app workload, kept off the manager. `max_replicas_per_node: 2` forces a 2/1 spread across the two workers instead of all 3 landing on the same node. |
| `node-exporter`, `promtail` | **every node** (`mode: global`) | One agent per node so per-host metrics and logs are collected. |

Prometheus uses Swarm's built-in DNS service discovery (`tasks.minitwit`, `tasks.node-exporter`) to scrape **every** replica, not a single round-robin one.

#### Persistence & retention

| Stateful service | Volume | Retention |
| --- | --- | --- |
| Prometheus | `prometheus_data` → `/prometheus` | 7 days **OR** 512 MB on disk (whichever first) |
| Loki | `loki_data` → `/loki` | 7 days, enforced by the compactor (see `monitoring/loki-config.yaml`) |
| Grafana | `grafana_data` → `/var/lib/grafana` | unbounded (small DB: users, alerts, edited dashboards) |

These caps keep the manager droplet safe (~1 GB used out of 25 GB at steady state).

#### Resource limits

Every service declares both `reservations` (minimum guaranteed) and `limits` (hard cap). Limits prevent a runaway container from killing the whole droplet via OOM.

### 9. Schema Initialization (one-shot, decoupled from app boot)

**Where it runs:** as a dedicated step in `deploy.sh`, before `docker stack deploy`. The same step is mirrored in the CI `test` job.

**What it does:** runs `Base.metadata.create_all(bind=engine)` exactly once against MySQL via a throwaway container:
```bash
docker run --rm --env-file .env michaelfant/minitwitimage:latest \
  python -c "from db import init_db; init_db()"
```

**Why it is no longer done on app boot.** Originally `db.py` called `init_db()` at module import time, so DDL ran every time the application started. With the move to Docker Swarm (3 `minitwit` replicas across 2 worker nodes, plus 3 gunicorn workers per replica) this race condition surfaced in production:

```
pymysql.err.OperationalError: (1684, "Table 'minitwit'.'latest_command'
was skipped since its definition is being modified by concurrent DDL statement")
```

MySQL error **1684** is raised when two sessions try to alter or create the same table at the same time. With up to 9 processes (3 replicas × 3 workers) all calling `create_all()` in parallel during a `start-first` rolling deploy, the losers of the race crashed and Swarm flapped the service.

**Rule going forward — best practice:** the application image must never run schema migrations on startup. DDL is a deploy-time concern, not a runtime concern, and must be performed by exactly one process. App containers assume the schema already exists.

This pattern also matches how real migration tools (Alembic, Flyway, Liquibase) are run: as a separate, single-shot step in the pipeline, never embedded in the request-serving process.

### 10. Testing & Static Analysis

We integrated three levels of automated testing into the CI pipeline as a quality gate, so if any test fails, deployment is blocked:

* **Integration tests** (`minitwit_tests_refactor.py`) : tests core app functionality (register, login, messages, follow/unfollow) via HTTP requests
* **API tests** (`minitwit_sim_api_test.py`) : tests the simulator REST endpoints (`/register`, `/msgs`, `/fllws`, `/latest`)
* **UI & End-to-End tests** (`test_itu_minitwit_ui.py`) : uses Selenium with a remote Chrome container to interact with the browser UI and verify user registration both visually (flash message) and functionally (login)

The pipeline is structured as three sequential jobs in `.github/workflows/continuous-deployment.yml`:

1. **`static-analysis`** — runs all linters/formatters (see below)
2. **`test`** — needs `static-analysis`; spins up MySQL + the app + Selenium and runs the full test suite
3. **`build-and-deploy`** — needs `test`; only here are images pushed to Docker Hub and deployed to the Droplet

This ordering guarantees that **broken images never reach Docker Hub** and that **deployment never happens on a failing test suite**.

#### Static Analysis

We added five static analysis tools as quality gates, running before build and deploy:

* **`ruff`** : Python linter and formatter, catches errors, bad practices, unsorted imports
* **`codespell`** : misspelling checker for source code and comments
* **`mypy`** : Python static type checker (non-blocking — reports type issues without failing the build)
* **`hadolint`** : Dockerfile linter, checks best practices for all three Dockerfiles
* **`shellcheck`** : shell script linter, checks `control.sh` and `deploy.sh`

`hadolint` and `shellcheck` run exclusively in CI since Dockerfiles and shell scripts change rarely and these tools are not straightforward to install on Windows.

`ruff`, `codespell`, and `mypy` are also available locally via the `Makefile` for a faster feedback loop:

```bash
make install-dev   # one-time: install dev tooling
make lint          # ruff check + ruff format --check + codespell
make lint-fix      # auto-fix ruff issues + reformat
make typecheck     # mypy
make check         # full local CI mirror (lint)
```

Tool configuration lives in `pyproject.toml`.

### 11. Maintainability & Technical Debt (SonarCloud + Codacy)

We continuously measure maintainability and technical debt with two third-party services that scan every push and pull request:

* **[SonarCloud](https://sonarcloud.io)** — provides a Maintainability rating, Reliability rating, Security rating, code smells, bugs, vulnerabilities, duplications, cyclomatic complexity, and the SQALE technical-debt index (in minutes/days).
* **[Codacy](https://www.codacy.com)** — provides an aggregated quality grade based on multiple engines (`ruff`, `pylint`, `bandit`, `hadolint`, `shellcheck`).

Both run in `.github/workflows/code-quality.yml` and require the following GitHub Actions secrets:

| Secret | Where to obtain |
| --- | --- |
| `SONAR_TOKEN` | https://sonarcloud.io → Account → Security → Generate Token |
| `CODACY_PROJECT_TOKEN` | https://app.codacy.com → Project → Settings → Integrations → Project API |

Project configuration:

* **`sonar-project.properties`** — declares Sonar project key, sources, test paths, and exclusions
* **`.codacy.yml`** — declares Codacy excluded paths and enabled engines

We react on the issues these tools surface: prominent items (security smells, duplicated blocks, high-complexity functions) are addressed; new code must not regress the metrics. New issues introduced in a PR will appear directly in the SonarCloud / Codacy PR check.

> **AI Disclosure:** Portions of this codebase were generated or optimized using LLMs. All AI-generated logic has been reviewed and tested for accuracy and security.
