# Quickstart: GCP Cloud Workstations Developer Bootstrap

Get up and running with a production-grade, AI-powered cloud developer workstation in **under 3 minutes**.

This quickstart guides you through provisioning a Google Cloud Workstation equipped with **Claude Code**, **Google Antigravity CLI**, **Python 3.14 via uv**, **Node.js LTS**, and **Go 1.24+** on an `n2-standard-8` (8 vCPU, 32 GB RAM) instance.

---

## Choose Your Onboarding Track

Select either **Google Cloud Shell** (zero local installation required) or your **Local Terminal**.

````carousel
### Track 1: Google Cloud Shell (Recommended — Zero Local Setup)

Google Cloud Shell provides a browser-based terminal with `gcloud`, `terraform`, and active GCP credentials pre-installed.

1. **Open Google Cloud Shell**:
   Launch [shell.cloud.google.com](https://shell.cloud.google.com) and ensure your target project is active:
   ```bash
   gcloud config set project <YOUR_PROJECT_ID>
   ```

2. **Clone the Repository**:
   ```bash
   git clone https://github.com/your-org/ai-dev-workstation.git
   cd ai-dev-workstation
   ```

3. **Run the One-Line Setup**:
   ```bash
   ./setup.sh -n
   ```
   *(Flags: `-n` runs non-interactively using your active Cloud Shell project and authenticated email).*
<!-- slide -->
### Track 2: Local Terminal (macOS & Linux)

For developers deploying directly from their personal laptops or desktop environments.

1. **Verify Prerequisites**:
   Ensure `gcloud` and `terraform` are installed:
   ```bash
   # macOS via Homebrew:
   brew install --cask google-cloud-sdk
   brew install hashicorp/tap/terraform
   ```

2. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project <YOUR_PROJECT_ID>
   ```

3. **Clone & Execute Interactive Setup**:
   ```bash
   git clone https://github.com/your-org/ai-dev-workstation.git
   cd ai-dev-workstation
   ./setup.sh
   ```
   *(Follow the interactive discovery prompts to select or create a cluster and configuration).*
````

---

## 3-Minute Step-by-Step Walkthrough

### Step 1: Provisioning & Automated Bootstrap

Run the setup orchestrator:

```bash
./setup.sh
```

```text
================================================================================
       🚀 Google Cloud Workstations Developer Bootstrap Orchestrator           
================================================================================

==> Running pre-flight checks...
  -> gcloud CLI found: Google Cloud SDK 510.0.0
  -> terraform CLI found: 1.10.0
  -> GCP Project detected: my-dev-project
  -> Authenticated account detected: dev@example.com
[✔] Pre-flight checks passed (Project: my-dev-project, User: dev@example.com).
==> Discovering workstation clusters in region 'us-central1'...
[✔] Target Cluster resolved: ws-cluster (create_cluster=true)
[✔] Target Configuration resolved: ws-config (create_config=true)
[✔] Target Workstation resolved: ws-dev (User: dev@example.com)
==> Applying Terraform configuration...
[✔] Terraform apply completed successfully.
==> Starting workstation 'ws-dev'...
[✔] Workstation 'ws-dev' is running.
==> Pushing bootstrap provisioner script over SSH to 'ws-dev'...
[✔] Workstation bootstrap script completed successfully.
```

The script will output your connection credentials and endpoints:

```text
================================================================================
       🎉 Google Cloud Workstation Provisioned & Ready for Development!        
================================================================================
  🌐 Browser IDE Web Interface:
     https://ws-dev.ws-cluster.us-central1.workstations.cloud.google

  💻 Terminal SSH Access:
     gcloud workstations ssh ws-dev --cluster=ws-cluster --config=ws-config --region=us-central1
================================================================================
```

---

### Step 2: Connect to Your Workstation

You can access your environment in two ways:

#### Option A: Web Browser IDE (Code-OSS)
Click the **Browser IDE Web Interface** link printed in your terminal (or open Google Cloud Console &rarr; Cloud Workstations &rarr; Launch).

#### Option B: Terminal SSH
Run the generated SSH command from your local machine:
```bash
gcloud workstations ssh ws-dev \
  --cluster=ws-cluster \
  --config=ws-config \
  --region=us-central1
```

Upon logging in, you will be greeted by the **MOTD (Message of the Day)** displaying active toolchains, runtime paths, and cheat sheets.

---

### Step 3: Authenticate AI Developer Toolchains

Inside your workstation terminal, configure your AI coding companions:

#### 1. Google Antigravity CLI (`agy`)
Run the device authorization flow:
```bash
agy auth login
```

#### 2. Claude Code CLI (`claude`)
Choose either Google Cloud Vertex AI mode (recommended for GCP) or your direct Anthropic API key:

**Vertex AI Mode (Pre-configured by `setup.sh`)**:
`setup.sh` synchronizes your user Application Default Credentials (ADC), quota project, and `ANTHROPIC_VERTEX_PROJECT_ID` into your persistent `.bashrc`:
```bash
# Enable Vertex AI mode (already exported in .bashrc)
export CLAUDE_CODE_USE_VERTEX=1

# Start Claude Code immediately
claude
```

**Direct Anthropic API Key**:
```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Start Claude Code
claude
```

---

### Step 4: Verify Runtime Environments

Test each pre-configured developer toolchain inside your workstation:

```bash
# Verify Python 3.14 via uv
python3.14 --version
uv run python -c "import sys; print(f'Hello from {sys.version}')"

# Verify Node.js LTS and npm
node -v
npm -v

# Verify Go 1.24 SDK
go version

# Re-display the Welcome Guide and Shortcuts
motd
```

---

## Essential Knowledge

> [!IMPORTANT]
> ### Persistent vs. Ephemeral Filesystem Rules
> - **Always work in `/home/user`**: Your home directory is backed by a 200 GB persistent disk. Everything under `/home/user` (repositories, virtual environments, SDKs, and `~/.bashrc`) is preserved across VM stops/starts.
> - **Root `/` is ephemeral**: Do NOT install tools using `sudo apt-get` or modify files outside `/home/user`. The container root filesystem resets upon restart.

### Forward Local Ports

To preview web applications (e.g. running on port `3000` or `8080`) in your local machine's browser:

```bash
# Run on your local laptop/desktop:
gcloud workstations ssh ws-dev \
  --cluster=ws-cluster \
  --config=ws-config \
  --region=us-central1 \
  -- -L 3000:localhost:3000 -L 8080:localhost:8080
```

---

## Clean Teardown

To shut down and destroy all cloud resources when you are finished:

```bash
# Decommission all infrastructure
terraform destroy -auto-approve
```

For full architectural details, Terraform variable references, and enterprise network topologies, see [README.md](README.md).
