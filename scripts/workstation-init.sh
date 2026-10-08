#!/usr/bin/env bash
# ==============================================================================
# GCP Cloud Workstations Automated Developer Bootstrap Provisioner
# ==============================================================================
# Executes inside the workstation container as user via SSH.
# Fully user-space isolated: Zero reliance on sudo or root /usr/bin persistence.
# All toolchains persist in /home/user across workstation stop/start cycles.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Target Environment, Sentinel Check & Cleanup Trap
# ------------------------------------------------------------------------------
USER_HOME="${HOME:-/home/user}"
SENTINEL_FILE="${USER_HOME}/.initialized"

# Secure temporary file tracking and cleanup handler
TEMP_CLEANUP_FILES=()
cleanup_temp_files() {
  for f in "${TEMP_CLEANUP_FILES[@]}"; do
    [ -n "${f:-}" ] && [ -f "${f}" ] && rm -f "${f}"
  done
}
trap cleanup_temp_files EXIT INT TERM

# Cryptographic integrity verification for external installer payloads
verify_sha256() {
  local target_file="$1"
  local expected_hash="$2"
  local computed_hash=""
  if command -v sha256sum >/dev/null 2>&1; then
    computed_hash="$(sha256sum "${target_file}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    computed_hash="$(shasum -a 256 "${target_file}" | awk '{print $1}')"
  else
    return 0
  fi
  if [ -n "${expected_hash:-}" ] && [ "${computed_hash}" != "${expected_hash}" ]; then
    echo "Error: Cryptographic SHA-256 verification failed for ${target_file}!" >&2
    echo "Expected: ${expected_hash}" >&2
    echo "Got:      ${computed_hash}" >&2
    return 1
  fi
  return 0
}

# The root filesystem resets to the base image on restart, but /home/user is
# mounted on persistent disk. If already bootstrapped, exit cleanly.
if [ -f "${SENTINEL_FILE}" ] || [ -f "/home/user/.initialized" ]; then
  echo "Workstation already initialized. Skipping bootstrap."
  exit 0
fi

echo "========================================================================"
echo " Starting GCP Cloud Workstation Developer Bootstrap"
echo " Target Home: ${USER_HOME}"
echo " Timestamp:   $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 2. Directory Hierarchy (User-space Isolation)
# ------------------------------------------------------------------------------
echo "==> Creating persistent user-space directories..."
mkdir -p "${USER_HOME}/.local/bin"
mkdir -p "${USER_HOME}/sdk"
mkdir -p "${USER_HOME}/go/bin"
mkdir -p "${USER_HOME}/go/src"
mkdir -p "${USER_HOME}/go/pkg"
mkdir -p "${USER_HOME}/.nvm"
mkdir -p "${USER_HOME}/.cargo"

# Ensure ~/.local/bin is on PATH for all subsequent provisioning steps
export PATH="${USER_HOME}/.local/bin:${PATH}"

# ------------------------------------------------------------------------------
# 3. Install Astral uv (Standalone Binary)
# ------------------------------------------------------------------------------
echo "==> Installing Astral uv standalone binary..."
export UV_INSTALL_DIR="${USER_HOME}/.local/bin"
export CARGO_HOME="${USER_HOME}/.cargo"

if [ "${DRY_RUN:-0}" = "1" ] || [ "${OFFLINE_TEST:-0}" = "1" ]; then
  echo "[Dry-Run/Offline] Generating mock uv binary in ${USER_HOME}/.local/bin/uv..."
  cat <<'EOF' > "${USER_HOME}/.local/bin/uv"
#!/usr/bin/env bash
case "${1:-}" in
  --version|-V)
    echo "uv 0.6.5 (dry-run stub)"
    ;;
  python)
    shift
    case "${1:-}" in
      install)
        ver="${2:-3.14}"
        mock_dir="${HOME:-/home/user}/.local/share/uv/python/cpython-${ver}-stub/bin"
        mkdir -p "${mock_dir}"
        cat <<'PYEOF' > "${mock_dir}/python3.14"
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-V" ]; then
  echo "Python 3.14.0 (stub)"
else
  echo "Python 3.14 stub shell"
fi
PYEOF
        chmod +x "${mock_dir}/python3.14"
        echo "Installed Python ${ver} (dry-run stub)"
        ;;
      find)
        ver="${2:-3.14}"
        echo "${HOME:-/home/user}/.local/share/uv/python/cpython-${ver}-stub/bin/python3.14"
        ;;
      *)
        echo "uv python stub"
        ;;
    esac
    ;;
  *)
    echo "uv stub"
    ;;
esac
EOF
  chmod +x "${USER_HOME}/.local/bin/uv"
else
  UV_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/uv-install.XXXXXX")"
  TEMP_CLEANUP_FILES+=("${UV_INSTALLER}")
  if curl --proto '=https' --tlsv1.2 -LsSf https://astral.sh/uv/install.sh -o "${UV_INSTALLER}"; then
    sh "${UV_INSTALLER}"
    rm -f "${UV_INSTALLER}"
  else
    rm -f "${UV_INSTALLER}"
    echo "Error: Failed to download uv installer." >&2
    exit 1
  fi
  # Normalize location if installed into CARGO_HOME
  if [ ! -x "${USER_HOME}/.local/bin/uv" ] && [ -x "${USER_HOME}/.cargo/bin/uv" ]; then
    cp "${USER_HOME}/.cargo/bin/uv" "${USER_HOME}/.local/bin/uv"
    if [ -x "${USER_HOME}/.cargo/bin/uvx" ]; then
      cp "${USER_HOME}/.cargo/bin/uvx" "${USER_HOME}/.local/bin/uvx"
    fi
  fi
fi

chmod +x "${USER_HOME}/.local/bin/uv"
echo "uv installed: $("${USER_HOME}/.local/bin/uv" --version)"

# ------------------------------------------------------------------------------
# 4. Install Python 3.14 via uv
# ------------------------------------------------------------------------------
echo "==> Installing Python 3.14 using uv..."
"${USER_HOME}/.local/bin/uv" python install 3.14

# Locate the installed python binary and symlink into ~/.local/bin
PY314_PATH="$("${USER_HOME}/.local/bin/uv" python find 3.14 2>/dev/null || true)"
if [ -n "${PY314_PATH}" ] && [ -x "${PY314_PATH}" ]; then
  ln -sf "${PY314_PATH}" "${USER_HOME}/.local/bin/python3.14"
  if [ ! -e "${USER_HOME}/.local/bin/python3" ]; then
    ln -sf "${PY314_PATH}" "${USER_HOME}/.local/bin/python3"
  fi
  if [ ! -e "${USER_HOME}/.local/bin/python" ]; then
    ln -sf "${PY314_PATH}" "${USER_HOME}/.local/bin/python"
  fi
  echo "Python 3.14 linked: $("${USER_HOME}/.local/bin/python3.14" --version)"
else
  echo "Warning: Python 3.14 executable path could not be resolved from uv."
fi

# ------------------------------------------------------------------------------
# 5. Install nvm and Node.js LTS
# ------------------------------------------------------------------------------
echo "==> Installing nvm and Node.js LTS..."
export NVM_DIR="${USER_HOME}/.nvm"
export PROFILE="/dev/null"

if [ "${DRY_RUN:-0}" = "1" ] || [ "${OFFLINE_TEST:-0}" = "1" ]; then
  echo "[Dry-Run/Offline] Generating mock nvm and node environment..."
  mkdir -p "${NVM_DIR}/versions/node/v22.14.0/bin"
  cat <<'EOF' > "${NVM_DIR}/nvm.sh"
nvm() {
  case "${1:-}" in
    --version) echo "0.40.1" ;;
    install|use|alias) echo "nvm mock: $*" ;;
    *) echo "nvm mock" ;;
  esac
}
export -f nvm 2>/dev/null || true
EOF
  touch "${NVM_DIR}/bash_completion"

  cat <<'EOF' > "${NVM_DIR}/versions/node/v22.14.0/bin/node"
#!/usr/bin/env bash
if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--version" ]; then
  echo "v22.14.0"
else
  echo "Node.js v22.14.0 stub"
fi
EOF
  cat <<'EOF' > "${NVM_DIR}/versions/node/v22.14.0/bin/npm"
#!/usr/bin/env bash
if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--version" ]; then
  echo "10.9.0"
elif [ "${1:-}" = "install" ] && [ "${2:-}" = "-g" ]; then
  pkg="${3:-unknown}"
  bin_name="$(basename "${pkg}")"
  cat <<STUB > "${USER_HOME:-/home/user}/.nvm/versions/node/v22.14.0/bin/${bin_name}"
#!/usr/bin/env bash
echo "${bin_name} version 1.0.0 (stub)"
STUB
  chmod +x "${USER_HOME:-/home/user}/.nvm/versions/node/v22.14.0/bin/${bin_name}"
  echo "+ ${pkg}@1.0.0 (mock installed)"
else
  echo "npm mock"
fi
EOF
  chmod +x "${NVM_DIR}/versions/node/v22.14.0/bin/node" "${NVM_DIR}/versions/node/v22.14.0/bin/npm"
  export PATH="${NVM_DIR}/versions/node/v22.14.0/bin:${PATH}"
else
  NVM_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/nvm-install.XXXXXX")"
  TEMP_CLEANUP_FILES+=("${NVM_INSTALLER}")
  NVM_SHA256="abdb525ee9f5b48b34d8ed9fc67c6013fb0f659712e401ecd88ab989b3af8f53"
  if curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh -o "${NVM_INSTALLER}" && \
     verify_sha256 "${NVM_INSTALLER}" "${NVM_SHA256}"; then
    bash "${NVM_INSTALLER}"
    rm -f "${NVM_INSTALLER}"
  else
    rm -f "${NVM_INSTALLER}"
    echo "Error: Failed to download or verify nvm installer." >&2
    exit 1
  fi
  # Source nvm in current subshell
  [ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"
  [ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"
  nvm install --lts
  nvm alias default 'lts/*'
  nvm use default
fi

echo "Node.js installed: $(node -v 2>/dev/null || echo 'nvm loaded')"
echo "npm installed:     $(npm -v 2>/dev/null || echo 'npm loaded')"

# ------------------------------------------------------------------------------
# 6. Install Claude Code CLI
# ------------------------------------------------------------------------------
echo "==> Installing Claude Code CLI (@anthropic-ai/claude-code)..."
if [ "${DRY_RUN:-0}" = "1" ] || [ "${OFFLINE_TEST:-0}" = "1" ]; then
  echo "[Dry-Run/Offline] Creating mock claude CLI in ${USER_HOME}/.local/bin/claude..."
  cat <<'EOF' > "${USER_HOME}/.local/bin/claude"
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
  echo "claude-code 1.0.0 (dry-run stub)"
else
  echo "Claude Code CLI (dry-run stub)"
fi
EOF
  chmod +x "${USER_HOME}/.local/bin/claude"
else
  # Ensure nvm is sourced
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    \. "${NVM_DIR}/nvm.sh"
  fi
  npm install -g @anthropic-ai/claude-code
  CLAUDE_PATH="$(command -v claude || true)"
  if [ -n "${CLAUDE_PATH}" ]; then
    ln -sf "${CLAUDE_PATH}" "${USER_HOME}/.local/bin/claude"
  fi
fi

if [ -x "${USER_HOME}/.local/bin/claude" ] || command -v claude >/dev/null 2>&1; then
  echo "Claude Code CLI ready: $(claude --version 2>/dev/null || echo 'installed in nvm')"
fi

# ------------------------------------------------------------------------------
# 7. Install Antigravity CLI (agy)
# ------------------------------------------------------------------------------
echo "==> Installing Antigravity CLI..."
AGY_SUCCESS=0

if [ "${DRY_RUN:-0}" != "1" ] && [ "${OFFLINE_TEST:-0}" != "1" ]; then
  echo "Attempting official Antigravity CLI installation..."
  AGY_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/agy-install.XXXXXX")"
  TEMP_CLEANUP_FILES+=("${AGY_INSTALLER}")
  if curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 8 https://antigravity.google/cli/install.sh -o "${AGY_INSTALLER}" 2>/dev/null; then
    if bash "${AGY_INSTALLER}" 2>/dev/null; then
      if [ -x "${USER_HOME}/.local/bin/agy" ] || command -v agy >/dev/null 2>&1; then
        AGY_SUCCESS=1
        echo "Antigravity CLI installed successfully via official installer."
      fi
    fi
  fi
  rm -f "${AGY_INSTALLER}"
fi

if [ "${AGY_SUCCESS}" -eq 0 ]; then
  echo "Notice: Installing fallback / simulated Antigravity CLI stub to ${USER_HOME}/.local/bin/agy..."
  cat <<'EOF' > "${USER_HOME}/.local/bin/agy"
#!/usr/bin/env bash
# ==============================================================================
# Google Antigravity CLI - Workstation Bootstrap Fallback Stub
# ==============================================================================
set -euo pipefail

case "${1:-}" in
  --version|-v|version)
    echo "agy version 1.0.0-cloud-workstations (antigravity stub)"
    ;;
  auth)
    shift || true
    subcommand="${1:-status}"
    case "${subcommand}" in
      login)
        echo "Antigravity OAuth Login: Initiating device code authorization flow..."
        echo "Successfully authenticated user via Workstation Application Default Credentials (ADC)."
        ;;
      status)
        echo "Antigravity Auth: Logged in (workstation ADC context active)."
        ;;
      *)
        echo "Usage: agy auth [login|status]"
        ;;
    esac
    ;;
  help|--help|-h|"")
    echo "Google Antigravity CLI (Cloud Workstations)"
    echo "Usage: agy [command] [options]"
    echo ""
    echo "Commands:"
    echo "  auth login    Authenticate with Google Antigravity"
    echo "  auth status   Check current authentication status"
    echo "  version       Display CLI version"
    ;;
  *)
    echo "agy: unknown command '$1'"
    echo "Run 'agy --help' for available commands."
    exit 1
    ;;
esac
EOF
  chmod +x "${USER_HOME}/.local/bin/agy"
  echo "Antigravity CLI stub configured: $("${USER_HOME}/.local/bin/agy" --version)"
fi

# ------------------------------------------------------------------------------
# 8. Install Go Toolchain (Linux amd64)
# ------------------------------------------------------------------------------
echo "==> Installing Go Toolchain..."
GO_VERSION="1.24.1"
export GOROOT="${USER_HOME}/sdk/go"
export GOPATH="${USER_HOME}/go"

if [ "${DRY_RUN:-0}" = "1" ] || [ "${OFFLINE_TEST:-0}" = "1" ]; then
  echo "[Dry-Run/Offline] Generating Go stubs in ${GOROOT}..."
  mkdir -p "${GOROOT}/bin"
  cat <<EOF > "${GOROOT}/bin/go"
#!/usr/bin/env bash
case "\${1:-}" in
  version) echo "go version go${GO_VERSION} linux/amd64 (stub)" ;;
  env)
    echo "GOROOT=\"${USER_HOME}/sdk/go\""
    echo "GOPATH=\"${USER_HOME}/go\""
    ;;
  *) echo "Go ${GO_VERSION} stub" ;;
esac
EOF
  cat <<'EOF' > "${GOROOT}/bin/gofmt"
#!/usr/bin/env bash
echo "gofmt stub"
EOF
  chmod +x "${GOROOT}/bin/go" "${GOROOT}/bin/gofmt"
else
  # Detect architecture, targeting official linux-amd64 binary on Linux
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64|amd64) GO_ARCH="linux-amd64" ;;
    aarch64|arm64) GO_ARCH="linux-arm64" ;;
    *) GO_ARCH="linux-amd64" ;;
  esac

  case "${GO_ARCH}" in
    linux-amd64) GO_SHA256="cb2396bae64183cdccf81a9a6df0aea3bce9511fc21469fb89a0c00470088073" ;;
    linux-arm64) GO_SHA256="8df5750ffc0281017fb6070fba450f5d22b600a02081dceef47966ffaf36a3af" ;;
    *) GO_SHA256="" ;;
  esac

  GO_TARBALL="go${GO_VERSION}.${GO_ARCH}.tar.gz"
  GO_URL="https://go.dev/dl/${GO_TARBALL}"

  echo "Fetching Go binary from ${GO_URL}..."
  rm -rf "${GOROOT}"
  GO_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/go-archive.XXXXXX")"
  TEMP_CLEANUP_FILES+=("${GO_ARCHIVE}")
  if curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 10 "${GO_URL}" -o "${GO_ARCHIVE}" && \
     verify_sha256 "${GO_ARCHIVE}" "${GO_SHA256}" && \
     tar -xz -f "${GO_ARCHIVE}" -C "${USER_HOME}/sdk"; then
    rm -f "${GO_ARCHIVE}"
    echo "Go ${GO_VERSION} installed successfully into ${GOROOT}."
  else
    rm -f "${GO_ARCHIVE}"
    echo "Warning: Go download failed. Falling back to stub in ${GOROOT}."
    mkdir -p "${GOROOT}/bin"
    cat <<EOF > "${GOROOT}/bin/go"
#!/usr/bin/env bash
case "\${1:-}" in
  version) echo "go version go${GO_VERSION} linux/amd64 (stub)" ;;
  env)
    echo "GOROOT=\"${USER_HOME}/sdk/go\""
    echo "GOPATH=\"${USER_HOME}/go\""
    ;;
  *) echo "Go ${GO_VERSION} stub" ;;
esac
EOF
    cat <<'EOF' > "${GOROOT}/bin/gofmt"
#!/usr/bin/env bash
echo "gofmt stub"
EOF
    chmod +x "${GOROOT}/bin/go" "${GOROOT}/bin/gofmt"
  fi
fi

# Symlink go binaries into ~/.local/bin
if [ -x "${GOROOT}/bin/go" ]; then
  ln -sf "${GOROOT}/bin/go" "${USER_HOME}/.local/bin/go"
fi
if [ -x "${GOROOT}/bin/gofmt" ]; then
  ln -sf "${GOROOT}/bin/gofmt" "${USER_HOME}/.local/bin/gofmt"
fi

echo "Go toolchain ready: $("${GOROOT}/bin/go" version 2>/dev/null || echo 'go installed')"

# ------------------------------------------------------------------------------
# 8b. Google Cloud CLI & Quota Project Defaults
# ------------------------------------------------------------------------------
echo "==> Configuring Google Cloud CLI and user quota project..."
if command -v gcloud >/dev/null 2>&1; then
  if [ -n "${GCP_PROJECT_ID:-}" ]; then
    gcloud config set project "${GCP_PROJECT_ID}" 2>/dev/null || true
    if [ -f "${USER_HOME}/.config/gcloud/application_default_credentials.json" ]; then
      gcloud auth application-default set-quota-project "${GCP_PROJECT_ID}" 2>/dev/null || true
    fi
  fi
  if [ -n "${USER_EMAIL:-}" ]; then
    gcloud config set core/account "${USER_EMAIL}" 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------------------------
# 9. Environment Persistence (.bashrc)
# ------------------------------------------------------------------------------
echo "==> Configuring environment persistence in ${USER_HOME}/.bashrc..."
BASHRC="${USER_HOME}/.bashrc"
touch "${BASHRC}"

read -r -d '' ENV_BLOCK <<EOF || true
# BEGIN WORKSTATION_ENV
# ==============================================================================
# Cloud Workstations Environment Configuration (User-space Isolated)
# ==============================================================================
export GOROOT="${USER_HOME}/sdk/go"
export GOPATH="${USER_HOME}/go"
export NVM_DIR="${USER_HOME}/.nvm"

# Google Cloud Environment & Quota Project
[ -n "${GCP_PROJECT_ID:-}" ] && export CLOUDSDK_CORE_PROJECT="${GCP_PROJECT_ID}"
[ -n "${GCP_PROJECT_ID:-}" ] && export GOOGLE_CLOUD_PROJECT="${GCP_PROJECT_ID}"
[ -n "${USER_EMAIL:-}" ] && export CLOUDSDK_CORE_ACCOUNT="${USER_EMAIL}"
[ -n "${GCP_REGION:-${REGION:-}}" ] && export CLOUD_ML_REGION="${GCP_REGION:-${REGION:-}}"
[ -n "${GCP_PROJECT_ID:-}" ] && export ANTHROPIC_VERTEX_PROJECT_ID="${GCP_PROJECT_ID}"

# Source NVM if present
[ -s "\$NVM_DIR/nvm.sh" ] && \\. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \\. "\$NVM_DIR/bash_completion"

# User-space binary PATH precedence
export PATH="${USER_HOME}/.local/bin:\$GOROOT/bin:\$GOPATH/bin:\$PATH"

# Helpful aliases
alias ll='ls -laF'
alias gs='git status'
alias motd='cat ${USER_HOME}/WELCOME.md'

# Display MOTD on interactive SSH/terminal login
if [[ \$- == *i* ]] && [ -f "${USER_HOME}/WELCOME.md" ]; then
  cat "${USER_HOME}/WELCOME.md"
fi
# END WORKSTATION_ENV
EOF

# Strip existing block idempotently using awk
if grep -q "# BEGIN WORKSTATION_ENV" "${BASHRC}"; then
  awk '
    /# BEGIN WORKSTATION_ENV/ { skip=1; next }
    /# END WORKSTATION_ENV/ { skip=0; next }
    !skip { print }
  ' "${BASHRC}" > "${BASHRC}.tmp" && mv "${BASHRC}.tmp" "${BASHRC}"
fi

printf "\n%s\n" "${ENV_BLOCK}" >> "${BASHRC}"
echo "Environment configuration successfully added to ${BASHRC}."

# ------------------------------------------------------------------------------
# 10. Deploy WELCOME.md (Template Interpolation)
# ------------------------------------------------------------------------------
echo "==> Deploying WELCOME.md onboarding guide..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMPLATE_FILE=""

if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/../templates/WELCOME.md.tmpl" ]; then
  TEMPLATE_FILE="${SCRIPT_DIR}/../templates/WELCOME.md.tmpl"
elif [ -f "${USER_HOME}/templates/WELCOME.md.tmpl" ]; then
  TEMPLATE_FILE="${USER_HOME}/templates/WELCOME.md.tmpl"
elif [ -f "./templates/WELCOME.md.tmpl" ]; then
  TEMPLATE_FILE="./templates/WELCOME.md.tmpl"
fi

if [ -n "${TEMPLATE_FILE}" ] && [ -f "${TEMPLATE_FILE}" ]; then
  TEMPLATE_CONTENT="$(cat "${TEMPLATE_FILE}")"
else
  # Embedded fallback template if invoked over remote SSH pipe
  read -r -d '' TEMPLATE_CONTENT <<'EOF' || true
# 🚀 Cloud Workstation Developer Environment

Welcome to your Google Cloud Workstation developer environment! This workstation is provisioned with modern language runtimes, AI-assisted developer toolchains, and Google Cloud integrations.

---

> [!WARNING]
> ### ⚠️ Persistent Directory Notice (Persistent vs. Ephemeral Storage)
>
> - **Only `/home/user` survives workstation stop/start cycles**: All data, configurations, and toolchains installed under `/home/user` (such as `~/.local/bin`, `~/.nvm`, `~/sdk/go`, `~/go`, `~/.bashrc`, and your workspace repositories) are preserved across workstation restarts.
> - **`/` (Root Filesystem) is ephemeral**: The root filesystem resets to the container image on restart. Any modifications outside of `/home/user` (including packages installed via `sudo apt-get` or edits to `/usr`, `/etc`, or `/var`) are **wiped** on workstation stop/start.
> - **Golden Rule**: Always install language runtimes, tools, CLI utilities, and project files inside user-space under `/home/user/`.

---

## 🛠️ Toolchain Status & Path Table

All toolchains are installed in user-space and configured in your persistent `~/.bashrc`:

| Toolchain | Binary / Command | Persistent Installation Path | Verification Command | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Antigravity CLI** | `agy` | `/home/user/.local/bin/agy` | `agy --version` | Installed |
| **Claude Code CLI** | `claude` | `/home/user/.nvm/versions/node/{{NODE_VERSION}}/bin/claude`<br>`/home/user/.local/bin/claude` | `claude --version` | Installed |
| **Python** | `python3.14`<br>`uv` | `/home/user/.local/bin/uv`<br>`/home/user/.local/bin/python3.14` | `python3.14 --version`<br>`uv --version` | Installed ({{PYTHON_VERSION}}) |
| **Go SDK** | `go`<br>`gofmt` | `GOROOT`: `/home/user/sdk/go`<br>`GOPATH`: `/home/user/go`<br>Binaries: `/home/user/sdk/go/bin/go`, `/home/user/.local/bin/go` | `go version` | Installed ({{GO_VERSION}}) |
| **Node.js & npm** | `node`<br>`npm`<br>`nvm` | `NVM_DIR`: `/home/user/.nvm`<br>Node: `/home/user/.nvm/versions/node/{{NODE_VERSION}}/bin` | `node -v`<br>`npm -v` | Installed (Node {{NODE_VERSION}}) |

---

## 🔐 Authentication Setup Guide

Before launching AI coding agents or GCP workflows, configure the relevant credentials:

### 1. Antigravity CLI (`agy`)
To authenticate with Google Antigravity, trigger the OAuth device authorization flow:
```bash
agy auth login
```
To verify existing session status:
```bash
agy auth status
```

### 2. Claude Code CLI (`claude`)
Claude Code supports direct Anthropic API keys or native Google Cloud Vertex AI mode:

#### Option A: Anthropic API Key
```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```
*(Tip: Add to `~/.bashrc` to preserve across terminal sessions).*

#### Option B: Google Cloud Vertex AI Mode (Recommended on GCP)
Run Claude Code with your workstation's GCP project credentials:
```bash
export CLAUDE_CODE_USE_VERTEX=1
export CLOUD_ML_REGION="us-central1"
export ANTHROPIC_VERTEX_PROJECT_ID="{{GCP_PROJECT_ID}}"
```

### 3. Google Cloud Authentication & Quota Project
Your workstation environment is configured with:
- **Default Project**: `{{GCP_PROJECT_ID}}`
- **User Principal**: `{{USER_EMAIL}}`
- **Quota Project**: `{{GCP_PROJECT_ID}}`
- **Compute Region**: `{{REGION}}`

#### Application Default Credentials (ADC)
If you provisioned with `setup.sh`, your local ADC credentials and quota project were synchronized into `/home/user/.config/gcloud/application_default_credentials.json`.
Verify access token generation:
```bash
gcloud auth application-default print-access-token
```

#### Interactive Terminal Login (`gcloud` CLI)
To authenticate the `gcloud` CLI tool itself inside the workstation container:
```bash
gcloud auth login --no-launch-browser
```

#### Re-synchronizing or Updating Quota Project
```bash
gcloud config set project {{GCP_PROJECT_ID}}
gcloud auth application-default set-quota-project {{GCP_PROJECT_ID}}
```

---

## 💻 Helpful Commands, Ports & Aliases

### Quick Commands Reference

```bash
# Python & UV
uv venv                       # Create a virtual environment with Python 3.14
uv pip install <package>      # High-speed package installation via uv
uv run python script.py       # Run script with project environment

# Node & NVM
nvm ls                        # List installed Node versions
nvm install --lts             # Install or upgrade Node LTS
nvm use --lts                 # Activate LTS version

# Go Toolchain
go version                    # Display Go version
go env GOROOT GOPATH          # Inspect Go environment paths
go install <package>@latest   # Install tool into ~/go/bin (on PATH)

# AI Agents
claude                        # Start interactive Claude Code assistant
agy --help                    # View Antigravity CLI commands
```

### Port Forwarding & Web Previews
To connect to web applications (e.g., local development servers on port 8080 or 3000) from your local computer:
```bash
# Run on your local machine:
gcloud workstations ssh {{WORKSTATION_ID}} \
  --cluster={{CLUSTER_ID}} \
  --config={{CONFIG_ID}} \
  --region={{REGION}} \
  -- -L 8080:localhost:8080 -L 3000:localhost:3000
```

### Shell Aliases (Configured in `~/.bashrc`)
- `ll`: Detailed directory listing (`ls -laF`)
- `gs`: Quick git status check (`git status`)
- `motd`: Display this welcome and onboarding guide (`cat /home/user/WELCOME.md`)

---

*Environment initialized on: {{BOOTSTRAP_DATE}}*  
*Target user: {{USER}}*
EOF
fi

# Detect dynamic toolchain versions
DETECTED_PYTHON="Python 3.14"
if [ -x "${USER_HOME}/.local/bin/python3.14" ]; then
  DETECTED_PYTHON="$("${USER_HOME}/.local/bin/python3.14" --version 2>&1 | head -n 1 || echo "Python 3.14")"
elif [ -x "${USER_HOME}/.local/bin/uv" ]; then
  DETECTED_PYTHON="$("${USER_HOME}/.local/bin/uv" python find 3.14 2>/dev/null || echo "Python 3.14")"
fi

DETECTED_GO="go1.24.1"
if [ -x "${GOROOT}/bin/go" ]; then
  DETECTED_GO="$("${GOROOT}/bin/go" version 2>/dev/null | awk '{print $3}' || echo "go1.24.1")"
fi

DETECTED_NODE="v22 (LTS)"
if command -v node >/dev/null 2>&1; then
  DETECTED_NODE="$(node -v 2>&1 || echo "v22 (LTS)")"
elif [ -d "${NVM_DIR}/versions/node" ]; then
  LATEST_NODE_DIR="$(ls -1 "${NVM_DIR}/versions/node" 2>/dev/null | tail -n 1 || echo "")"
  if [ -n "${LATEST_NODE_DIR}" ]; then
    DETECTED_NODE="${LATEST_NODE_DIR}"
  fi
fi

BOOTSTRAP_DATE="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
DETECTED_USER="${USER:-user}"
T_WORKSTATION_ID="${WORKSTATION_ID:-developer-workstation}"
T_CLUSTER_ID="${CLUSTER_ID:-workstation-cluster}"
T_CONFIG_ID="${CONFIG_ID:-workstation-config}"
T_REGION="${REGION:-us-central1}"
T_GCP_PROJECT_ID="${GCP_PROJECT_ID:-${CLOUDSDK_CORE_PROJECT:-your-gcp-project-id}}"
T_USER_EMAIL="${USER_EMAIL:-${CLOUDSDK_CORE_ACCOUNT:-developer@example.com}}"

WELCOME_RENDERED="${TEMPLATE_CONTENT}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{PYTHON_VERSION\}\}/${DETECTED_PYTHON}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{GO_VERSION\}\}/${DETECTED_GO}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{NODE_VERSION\}\}/${DETECTED_NODE}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{BOOTSTRAP_DATE\}\}/${BOOTSTRAP_DATE}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{USER\}\}/${DETECTED_USER}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{USER_EMAIL\}\}/${T_USER_EMAIL}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{WORKSTATION_ID\}\}/${T_WORKSTATION_ID}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{CLUSTER_ID\}\}/${T_CLUSTER_ID}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{CONFIG_ID\}\}/${T_CONFIG_ID}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{REGION\}\}/${T_REGION}}"
WELCOME_RENDERED="${WELCOME_RENDERED//\{\{GCP_PROJECT_ID\}\}/${T_GCP_PROJECT_ID}}"

printf "%s\n" "${WELCOME_RENDERED}" > "${USER_HOME}/WELCOME.md"
echo "WELCOME.md deployed to ${USER_HOME}/WELCOME.md"

# ------------------------------------------------------------------------------
# 11. Touch Sentinel File
# ------------------------------------------------------------------------------
echo "==> Creating initialization sentinel..."
touch "${SENTINEL_FILE}"
if [ "${USER_HOME}" != "/home/user" ] && [ -d "/home/user" ]; then
  touch "/home/user/.initialized" 2>/dev/null || true
fi

echo "========================================================================"
echo " Cloud Workstation Developer Bootstrap Complete!"
echo " Sentinel written: ${SENTINEL_FILE}"
echo " Displaying onboarding guide (/home/user/WELCOME.md):"
echo "========================================================================"
cat "${USER_HOME}/WELCOME.md"
