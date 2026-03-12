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

> **AI Disclosure:** Portions of this codebase were generated or optimized using LLMs. All AI-generated logic has been reviewed and tested for accuracy and security.
