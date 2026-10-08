#!/usr/bin/env bash
# ==============================================================================
# GCP Cloud Workstations Automated Developer Bootstrap: Orchestrator
# ==============================================================================
# End-to-end setup script for discovering, configuring, provisioning, starting,
# and bootstrapping Google Cloud Workstations with Terraform and SSH.
#
# Portability: Compatible with macOS (/bin/bash 3.2+, zsh) and Linux (Cloud Shell).
# ==============================================================================

# If invoked directly via zsh, enable standard array indexing and word splitting
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null || true
  setopt SH_WORD_SPLIT 2>/dev/null || true
fi

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Environment & Path Normalization
# ------------------------------------------------------------------------------
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
else
  SCRIPT_PATH="$0"
fi
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
cd "${SCRIPT_DIR}"

# ------------------------------------------------------------------------------
# 2. Terminal Styling & Logging Helpers
# ------------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  GREEN="\033[32m"
  CYAN="\033[36m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  MAGENTA="\033[35m"
  RED="\033[31m"
  RESET="\033[0m"
else
  BOLD=""
  DIM=""
  GREEN=""
  CYAN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  RED=""
  RESET=""
fi

log_info()    { printf "%b==>%b %s\n" "${BLUE}${BOLD}" "${RESET}" "$*"; }
log_step()    { printf "  %b->%b %s\n" "${CYAN}" "${RESET}" "$*"; }
log_success() { printf "%b[✔]%b %s\n" "${GREEN}${BOLD}" "${RESET}" "$*"; }
log_warn()    { printf "%b[!]%b %s\n" "${YELLOW}${BOLD}" "${RESET}" "$*"; }
log_error()   { printf "%b[✘]%b %s\n" "${RED}${BOLD}" "${RESET}" "$*" >&2; }

log_progress() {
  local msg="$1"
  if [ -t 1 ]; then
    printf "\r\033[K%b[..]%b %s" "${CYAN}" "${RESET}" "$msg"
  else
    printf "[..] %s\n" "$msg"
  fi
}

log_progress_done() {
  local msg="$1"
  if [ -t 1 ]; then
    printf "\r\033[K%b[✔]%b %s\n" "${GREEN}${BOLD}" "${RESET}" "$msg"
  else
    printf "[✔] %s\n" "$msg"
  fi
}

# ------------------------------------------------------------------------------
# 3. Cleanup & Signal Handlers
# ------------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  if [ -t 1 ]; then
    tput cnorm 2>/dev/null || printf "\033[?25h"
  fi
  # Clean up any temporary files
  if [ -n "${TMP_VARS:-}" ] && [ -f "${TMP_VARS}" ]; then
    rm -f "${TMP_VARS}"
  fi
  if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ] && [ $exit_code -ne 143 ]; then
    log_error "Setup encountered an error and halted (exit code ${exit_code})."
  fi
}
trap cleanup EXIT
trap 'printf "\n"; log_warn "Setup cancelled by user."; exit 130' INT
trap 'printf "\n"; log_warn "Setup terminated."; exit 143' TERM

# ------------------------------------------------------------------------------
# 4. CLI Argument Defaults & Parsing
# ------------------------------------------------------------------------------
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # Load environment variables from .env file if present
  set -a
  # shellcheck source=/dev/null
  . "${SCRIPT_DIR}/.env"
  set +a
fi

REGION="${REGION:-${GCP_REGION:-us-central1}}"
DRY_RUN=false
NON_INTERACTIVE=false

CLI_PROJECT_ID="${GCP_PROJECT_ID:-${PROJECT_ID:-}}"
CLI_USER_EMAIL="${USER_EMAIL:-}"
CLI_CLUSTER_ID="${CLUSTER_ID:-}"
CLI_CONFIG_ID="${CONFIG_ID:-}"
CLI_WORKSTATION_ID="${WORKSTATION_ID:-}"
CLI_MACHINE_TYPE="${MACHINE_TYPE:-n2-standard-8}"

print_usage() {
  cat <<EOF
Usage: ./setup.sh [OPTIONS]

Automated setup, provisioning, and bootstrap orchestrator for GCP Cloud Workstations.

Options:
  -r, --region <region>         GCP region (default: us-central1)
  -d, --dry-run                 Simulate API calls and actions without provisioning
  -n, -y, --non-interactive     Non-interactive mode (use defaults / flags / env vars)
  -p, --project <project_id>    GCP Project ID override
  -e, --email <user_email>      Workstation user email override
  -c, --cluster <cluster_id>    Target workstation cluster ID
      --config <config_id>      Target workstation config ID
  -w, --workstation <id>        Target workstation ID
  -m, --machine-type <type>     Compute Engine machine type (default: n2-standard-8)
  -h, --help                    Show this help message and exit

Environment Variables:
  REGION, GCP_REGION            GCP region (default: us-central1)
  PROJECT_ID, GCP_PROJECT_ID    GCP project ID
  USER_EMAIL                    Workstation user email
  CLUSTER_ID                    Target workstation cluster ID
  CONFIG_ID                     Target workstation config ID
  WORKSTATION_ID                Target workstation ID
  MACHINE_TYPE                  Compute Engine machine type (default: n2-standard-8)
  NON_INTERACTIVE               Run non-interactively if set to 1 or true
  DRY_RUN                       Simulate actions if set to 1 or true
  NO_COLOR                      Disable colored ANSI output

EOF
}

# Honor environment variable flags if set
if [ "${DRY_RUN:-0}" = "1" ] || [ "${DRY_RUN:-false}" = "true" ]; then
  DRY_RUN=true
fi
if [ "${NON_INTERACTIVE:-0}" = "1" ] || [ "${NON_INTERACTIVE:-false}" = "true" ]; then
  NON_INTERACTIVE=true
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --region|-r)
      REGION="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --dry-run|-d)
      DRY_RUN=true
      shift
      ;;
    --non-interactive|-n|-y|--yes)
      NON_INTERACTIVE=true
      shift
      ;;
    --project|-p)
      CLI_PROJECT_ID="$2"
      shift 2
      ;;
    --project=*)
      CLI_PROJECT_ID="${1#*=}"
      shift
      ;;
    --email|-e)
      CLI_USER_EMAIL="$2"
      shift 2
      ;;
    --email=*)
      CLI_USER_EMAIL="${1#*=}"
      shift
      ;;
    --cluster|-c)
      CLI_CLUSTER_ID="$2"
      shift 2
      ;;
    --cluster=*)
      CLI_CLUSTER_ID="${1#*=}"
      shift
      ;;
    --config)
      CLI_CONFIG_ID="$2"
      shift 2
      ;;
    --config=*)
      CLI_CONFIG_ID="${1#*=}"
      shift
      ;;
    --workstation|-w)
      CLI_WORKSTATION_ID="$2"
      shift 2
      ;;
    --workstation=*)
      CLI_WORKSTATION_ID="${1#*=}"
      shift
      ;;
    --machine-type|-m)
      CLI_MACHINE_TYPE="$2"
      shift 2
      ;;
    --machine-type=*)
      CLI_MACHINE_TYPE="${1#*=}"
      shift
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      echo ""
      print_usage
      exit 1
      ;;
  esac
done

# ------------------------------------------------------------------------------
# 5. Validation & Helper Functions (POSIX / Bash 3.2 Compatible)
# ------------------------------------------------------------------------------
is_valid_id() {
  local id="$1"
  local regex="^[a-z][a-z0-9-]{0,62}$"
  if [[ "$id" =~ $regex ]]; then
    return 0
  else
    return 1
  fi
}

is_valid_email() {
  local email="$1"
  local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
  if [[ "$email" =~ $regex ]]; then
    return 0
  else
    return 1
  fi
}

sanitize_email() {
  local email="$1"
  local user_part="${email%%@*}"
  # Convert to lowercase
  local clean="$(printf "%s" "$user_part" | tr '[:upper:]' '[:lower:]')"
  # Replace non-alphanumeric with hyphen
  clean="$(printf "%s" "$clean" | sed 's/[^a-z0-9]/-/g')"
  # Collapse multiple hyphens
  clean="$(printf "%s" "$clean" | sed 's/-\{2,\}/-/g')"
  # Strip leading and trailing hyphens
  clean="$(printf "%s" "$clean" | sed 's/^-//; s/-$//')"
  # Ensure ws- prefix
  if [[ "$clean" != ws-* ]]; then
    clean="ws-${clean}"
  fi
  # Enforce max 63 chars
  clean="$(printf "%s" "$clean" | cut -c 1-63)"
  clean="$(printf "%s" "$clean" | sed 's/-$//')"
  printf "%s" "$clean"
}

escape_hcl_string() {
  local str="$1"
  str="${str//\\/\\\\}"
  str="${str//\"/\\\"}"
  printf "%s" "$str"
}

prompt_yes_no() {
  local prompt_msg="$1"
  local default_val="${2:-Y}"
  local choice
  while true; do
    if [ "$default_val" = "Y" ]; then
      printf >&2 "%b%s [Y/n]: %b" "${BOLD}" "$prompt_msg" "${RESET}"
      read -r choice || choice=""
      choice="${choice:-Y}"
    else
      printf >&2 "%b%s [y/N]: %b" "${BOLD}" "$prompt_msg" "${RESET}"
      read -r choice || choice=""
      choice="${choice:-N}"
    fi
    case "$choice" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) log_warn "Please answer yes (y) or no (n)." ;;
    esac
  done
}

prompt_valid_id() {
  local prompt_msg="$1"
  local default_val="$2"
  local id_out
  while true; do
    if [ -n "$default_val" ]; then
      printf >&2 "%b%s [default: %s]: %b" "${BOLD}" "$prompt_msg" "$default_val" "${RESET}"
      read -r id_out || id_out=""
      id_out="${id_out:-$default_val}"
    else
      printf >&2 "%b%s: %b" "${BOLD}" "$prompt_msg" "${RESET}"
      read -r id_out || id_out=""
    fi
    id_out="$(echo "$id_out" | tr -d ' ')"
    if is_valid_id "$id_out"; then
      printf "%s" "$id_out"
      return 0
    else
      log_warn "Invalid ID '${id_out}'. Must match ^[a-z][a-z0-9-]{0,62}$ (lowercase letters, numbers, hyphens; starts with a letter; max 63 chars)."
    fi
  done
}

# ------------------------------------------------------------------------------
# 6. Banner & Initialization
# ------------------------------------------------------------------------------
printf "\n"
printf "%b================================================================================%b\n" "${BLUE}${BOLD}" "${RESET}"
printf "%b       🚀 Google Cloud Workstations Developer Bootstrap Orchestrator           %b\n" "${CYAN}${BOLD}" "${RESET}"
printf "%b================================================================================%b\n\n" "${BLUE}${BOLD}" "${RESET}"

if [ "$DRY_RUN" = "true" ]; then
  log_warn "DRY-RUN MODE ENABLED: Simulating API calls and actions without modifying infrastructure."
fi

# Verify repository files
if [ ! -f "main.tf" ] || [ ! -f "variables.tf" ]; then
  log_error "Terraform configuration files (main.tf, variables.tf) not found in current directory (${PWD})."
  exit 1
fi
if [ ! -f "scripts/workstation-init.sh" ]; then
  log_error "Bootstrap provisioner script 'scripts/workstation-init.sh' not found."
  exit 1
fi

# ------------------------------------------------------------------------------
# 7. Pre-flight Tooling & Identity Checks
# ------------------------------------------------------------------------------
log_info "Running pre-flight checks..."

# Check gcloud
if ! command -v gcloud >/dev/null 2>&1; then
  log_error "'gcloud' CLI is not installed or not found in PATH."
  cat <<'EOF' >&2

Actionable Installation Instructions:
  - macOS (Homebrew):
      brew install --cask google-cloud-sdk
  - Linux / Cloud Shell:
      Follow the official installation guide: https://cloud.google.com/sdk/docs/install
  - Documentation:
      https://cloud.google.com/sdk/docs/install

EOF
  exit 1
fi
log_step "gcloud CLI found: $(gcloud --version 2>/dev/null | head -n1)"

# Check terraform
if ! command -v terraform >/dev/null 2>&1; then
  log_error "'terraform' CLI is not installed or not found in PATH."
  cat <<'EOF' >&2

Actionable Installation Instructions:
  - macOS (Homebrew):
      brew tap hashicorp/tap
      brew install hashicorp/tap/terraform
  - Linux:
      https://developer.hashicorp.com/terraform/install
  - Documentation:
      https://developer.hashicorp.com/terraform/downloads

EOF
  exit 1
fi
log_step "terraform CLI found: $(terraform version -json 2>/dev/null | grep '"version"' | cut -d'"' -f4 || terraform version | head -n1)"

# Check Application Default Credentials (ADC) for Terraform
if [ "$DRY_RUN" != "true" ]; then
  log_info "Verifying Application Default Credentials (ADC) for Terraform..."
  ADC_ERR="$(gcloud auth application-default print-access-token 2>&1 >/dev/null || true)"
  if [ -n "${ADC_ERR}" ]; then
    if echo "${ADC_ERR}" | grep -q "Invalid JWT Signature"; then
      log_error "Google Application Default Credentials error: 'Invalid JWT Signature'."
      if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
        log_warn "GOOGLE_APPLICATION_CREDENTIALS is set to: ${GOOGLE_APPLICATION_CREDENTIALS}"
        log_warn "This service account key appears to be revoked, deleted, or invalid in GCP IAM."
        if [ "$NON_INTERACTIVE" != "true" ]; then
          if prompt_yes_no "Unset GOOGLE_APPLICATION_CREDENTIALS for this session and run 'gcloud auth application-default login'?" "Y"; then
            unset GOOGLE_APPLICATION_CREDENTIALS
            gcloud auth application-default login
          else
            log_error "Cannot proceed with Terraform apply while GOOGLE_APPLICATION_CREDENTIALS is invalid."
            exit 1
          fi
        else
          log_error "Invalid GOOGLE_APPLICATION_CREDENTIALS. Unset it or re-authenticate with 'gcloud auth application-default login'."
          exit 1
        fi
      fi
    elif echo "${ADC_ERR}" | grep -q "credentials were not found"; then
      log_warn "Application Default Credentials (ADC) not configured."
      log_warn "Terraform requires ADC to authenticate against Google Cloud APIs."
      if [ "$NON_INTERACTIVE" != "true" ]; then
        if prompt_yes_no "Run 'gcloud auth application-default login' now?" "Y"; then
          gcloud auth application-default login
        else
          log_error "Cannot proceed with Terraform apply without valid Application Default Credentials."
          exit 1
        fi
      else
        log_error "Missing Application Default Credentials. Run 'gcloud auth application-default login' first."
        exit 1
      fi
    fi
  else
    log_step "Application Default Credentials (ADC) verified for Terraform."
  fi
fi

# Active GCP Project resolution
PROJECT_ID=""
if [ -n "${CLI_PROJECT_ID}" ]; then
  PROJECT_ID="${CLI_PROJECT_ID}"
  log_step "GCP Project specified via CLI/env: ${PROJECT_ID}"
else
  DETECTED_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
  if [ "${DETECTED_PROJECT}" = "(unset)" ] || [ -z "${DETECTED_PROJECT}" ]; then
    DETECTED_PROJECT=""
  fi

  if [ -n "${DETECTED_PROJECT}" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      PROJECT_ID="${DETECTED_PROJECT}"
      log_step "GCP Project detected: ${PROJECT_ID}"
    else
      if prompt_yes_no "Use active GCP Project '${DETECTED_PROJECT}'?" "Y"; then
        PROJECT_ID="${DETECTED_PROJECT}"
      else
        while [ -z "${PROJECT_ID}" ]; do
          printf "%bEnter GCP Project ID: %b" "${BOLD}" "${RESET}"
          read -r PROJECT_ID || PROJECT_ID=""
          PROJECT_ID="$(echo "${PROJECT_ID}" | tr -d ' ')"
          if [ -z "${PROJECT_ID}" ]; then
            log_warn "GCP Project ID cannot be empty."
          fi
        done
      fi
    fi
  else
    if [ "$NON_INTERACTIVE" = "true" ]; then
      log_error "No active GCP project found in gcloud config. Specify --project <id> or set PROJECT_ID env var."
      exit 1
    else
      while [ -z "${PROJECT_ID}" ]; do
        printf "%bEnter GCP Project ID: %b" "${BOLD}" "${RESET}"
        read -r PROJECT_ID || PROJECT_ID=""
        PROJECT_ID="$(echo "${PROJECT_ID}" | tr -d ' ')"
        if [ -z "${PROJECT_ID}" ]; then
          log_warn "GCP Project ID cannot be empty."
        fi
      done
    fi
  fi
fi

# Active GCP User Email resolution
USER_EMAIL=""
if [ -n "${CLI_USER_EMAIL}" ]; then
  USER_EMAIL="${CLI_USER_EMAIL}"
  log_step "User email specified via CLI/env: ${USER_EMAIL}"
else
  DETECTED_EMAIL="$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n 1 || true)"
  if [ -n "${DETECTED_EMAIL}" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      USER_EMAIL="${DETECTED_EMAIL}"
      log_step "Authenticated account detected: ${USER_EMAIL}"
    else
      if prompt_yes_no "Use authenticated account '${DETECTED_EMAIL}' for workstation IAM binding?" "Y"; then
        USER_EMAIL="${DETECTED_EMAIL}"
      else
        while true; do
          printf "%bEnter user email for workstation IAM binding: %b" "${BOLD}" "${RESET}"
          read -r USER_EMAIL || USER_EMAIL=""
          USER_EMAIL="$(echo "${USER_EMAIL}" | tr -d ' ')"
          if is_valid_email "${USER_EMAIL}"; then
            break
          else
            log_warn "Invalid email format '${USER_EMAIL}'. Expected user@example.com."
          fi
        done
      fi
    fi
  else
    if [ "$NON_INTERACTIVE" = "true" ]; then
      log_error "No authenticated account found in gcloud. Run 'gcloud auth login' or specify --email <address>."
      exit 1
    else
      while true; do
        printf "%bEnter user email for workstation IAM binding: %b" "${BOLD}" "${RESET}"
        read -r USER_EMAIL || USER_EMAIL=""
        USER_EMAIL="$(echo "${USER_EMAIL}" | tr -d ' ')"
        if is_valid_email "${USER_EMAIL}"; then
          break
        else
          log_warn "Invalid email format '${USER_EMAIL}'. Expected user@example.com."
        fi
      done
    fi
  fi
fi

if ! is_valid_email "${USER_EMAIL}"; then
  log_error "User email '${USER_EMAIL}' is not a valid email address."
  exit 1
fi

log_success "Pre-flight checks passed (Project: ${PROJECT_ID}, User: ${USER_EMAIL}, Region: ${REGION})."

# ------------------------------------------------------------------------------
# 8. Cluster Discovery & Selection
# ------------------------------------------------------------------------------
log_info "Discovering workstation clusters in region '${REGION}'..."

clusters=()
# If in dry-run and mock clusters are provided via environment, support offline testing
if [ "$DRY_RUN" = "true" ] && [ -n "${MOCK_CLUSTERS:-}" ]; then
  IFS=',' read -r -a clusters <<< "${MOCK_CLUSTERS}"
else
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    clusters+=("$line")
  done < <(gcloud workstations clusters list --project="${PROJECT_ID}" --region="${REGION}" --format="value(name.basename())" 2>/dev/null || true)
fi

CLUSTER_ID=""
CREATE_CLUSTER=false

if [ -n "${CLI_CLUSTER_ID}" ]; then
  CLUSTER_ID="${CLI_CLUSTER_ID}"
  CREATE_CLUSTER=true
  if [ ${#clusters[@]} -gt 0 ]; then
    for c in "${clusters[@]}"; do
      if [ "$c" = "${CLUSTER_ID}" ]; then
        CREATE_CLUSTER=false
        break
      fi
    done
  fi
  log_step "Cluster ID explicitly specified: ${CLUSTER_ID} (create_cluster=${CREATE_CLUSTER})"
elif [ ${#clusters[@]} -eq 0 ]; then
  log_warn "No existing workstation clusters found in region '${REGION}'."
  CREATE_CLUSTER=true
  if [ "$NON_INTERACTIVE" = "true" ]; then
    CLUSTER_ID="ws-cluster"
    log_step "Non-interactive: creating new cluster '${CLUSTER_ID}'."
  else
    CLUSTER_ID="$(prompt_valid_id "Enter new cluster ID to create" "ws-cluster")"
  fi
elif [ ${#clusters[@]} -eq 1 ]; then
  FOUND_CLUSTER="${clusters[0]}"
  log_step "Found 1 existing cluster in region '${REGION}': ${FOUND_CLUSTER}"
  if [ "$NON_INTERACTIVE" = "true" ]; then
    CLUSTER_ID="${FOUND_CLUSTER}"
    CREATE_CLUSTER=false
    log_step "Non-interactive: using existing cluster '${CLUSTER_ID}'."
  else
    if prompt_yes_no "Use existing cluster '${FOUND_CLUSTER}'?" "Y"; then
      CLUSTER_ID="${FOUND_CLUSTER}"
      CREATE_CLUSTER=false
    else
      CREATE_CLUSTER=true
      CLUSTER_ID="$(prompt_valid_id "Enter new cluster ID to create" "ws-cluster")"
    fi
  fi
else
  log_step "Found ${#clusters[@]} existing clusters in region '${REGION}':"
  NEW_CLUSTER_OPT=$((${#clusters[@]} + 1))
  for ((i = 0; i < ${#clusters[@]}; i++)); do
    printf "    [%d] %s\n" "$((i + 1))" "${clusters[i]}"
  done
  printf "    [%d] Create new cluster...\n" "${NEW_CLUSTER_OPT}"

  if [ "$NON_INTERACTIVE" = "true" ]; then
    CLUSTER_ID="${clusters[0]}"
    CREATE_CLUSTER=false
    log_step "Non-interactive: defaulting to first cluster '${CLUSTER_ID}'."
  else
    while true; do
      printf "%bSelect an option [1-%d]: %b" "${BOLD}" "${NEW_CLUSTER_OPT}" "${RESET}"
      read -r choice || choice=""
      choice="$(echo "${choice}" | tr -d ' ')"
      if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${NEW_CLUSTER_OPT}" ]; then
        if [ "${choice}" -eq "${NEW_CLUSTER_OPT}" ]; then
          CREATE_CLUSTER=true
          CLUSTER_ID="$(prompt_valid_id "Enter new cluster ID to create" "ws-cluster")"
        else
          CREATE_CLUSTER=false
          CLUSTER_ID="${clusters[$((choice - 1))]}"
        fi
        break
      else
        log_warn "Please enter a valid choice between 1 and ${NEW_CLUSTER_OPT}."
      fi
    done
  fi
fi

if ! is_valid_id "${CLUSTER_ID}"; then
  log_error "Cluster ID '${CLUSTER_ID}' is invalid. Must match ^[a-z][a-z0-9-]{0,62}$."
  exit 1
fi
log_success "Target Cluster resolved: ${CLUSTER_ID} (create_cluster=${CREATE_CLUSTER})"

# ------------------------------------------------------------------------------
# 9. Configuration Discovery & Selection
# ------------------------------------------------------------------------------
TARGET_MACHINE_TYPE="${CLI_MACHINE_TYPE:-n2-standard-8}"
CONFIG_ID=""
CREATE_CONFIG=false

if [ "${CREATE_CLUSTER}" = "true" ]; then
  log_info "New cluster '${CLUSTER_ID}' will be created; creating new workstation configuration with ${TARGET_MACHINE_TYPE} specs."
  CREATE_CONFIG=true
  if [ -n "${CLI_CONFIG_ID}" ]; then
    CONFIG_ID="${CLI_CONFIG_ID}"
  elif [ "$NON_INTERACTIVE" = "true" ]; then
    CONFIG_ID="ws-config"
  else
    CONFIG_ID="$(prompt_valid_id "Enter configuration ID to create" "ws-config")"
  fi
else
  log_info "Discovering workstation configurations in cluster '${CLUSTER_ID}'..."
  configs=()
  if [ "$DRY_RUN" = "true" ] && [ -n "${MOCK_CONFIGS:-}" ]; then
    IFS=',' read -r -a configs <<< "${MOCK_CONFIGS}"
  else
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      configs+=("$line")
    done < <(gcloud workstations configs list --cluster="${CLUSTER_ID}" --project="${PROJECT_ID}" --region="${REGION}" --format="value(name.basename())" 2>/dev/null || true)
  fi

  if [ -n "${CLI_CONFIG_ID}" ]; then
    CONFIG_ID="${CLI_CONFIG_ID}"
    CREATE_CONFIG=true
    if [ ${#configs[@]} -gt 0 ]; then
      for c in "${configs[@]}"; do
        if [ "$c" = "${CONFIG_ID}" ]; then
          CREATE_CONFIG=false
          break
        fi
      done
    fi
    log_step "Configuration ID explicitly specified: ${CONFIG_ID} (create_config=${CREATE_CONFIG})"
  elif [ ${#configs[@]} -eq 0 ]; then
    log_warn "No existing configurations found in cluster '${CLUSTER_ID}'."
    CREATE_CONFIG=true
    if [ "$NON_INTERACTIVE" = "true" ]; then
      CONFIG_ID="ws-config"
      log_step "Non-interactive: creating new configuration '${CONFIG_ID}'."
    else
      CONFIG_ID="$(prompt_valid_id "Enter configuration ID to create with high-performance ${TARGET_MACHINE_TYPE} specs" "ws-config")"
    fi
  elif [ ${#configs[@]} -eq 1 ]; then
    FOUND_CONFIG="${configs[0]}"
    log_step "Found 1 existing configuration in cluster '${CLUSTER_ID}': ${FOUND_CONFIG}"
    if [ "$NON_INTERACTIVE" = "true" ]; then
      CONFIG_ID="${FOUND_CONFIG}"
      CREATE_CONFIG=false
      log_step "Non-interactive: using existing configuration '${CONFIG_ID}'."
    else
      if prompt_yes_no "Use existing configuration '${FOUND_CONFIG}'?" "Y"; then
        CONFIG_ID="${FOUND_CONFIG}"
        CREATE_CONFIG=false
      else
        CREATE_CONFIG=true
        CONFIG_ID="$(prompt_valid_id "Enter new configuration ID to create with high-performance ${TARGET_MACHINE_TYPE} specs" "ws-config")"
      fi
    fi
  else
    log_step "Found ${#configs[@]} existing configurations in cluster '${CLUSTER_ID}':"
    NEW_CONFIG_OPT=$((${#configs[@]} + 1))
    for ((i = 0; i < ${#configs[@]}; i++)); do
      printf "    [%d] %s\n" "$((i + 1))" "${configs[i]}"
    done
    printf "    [%d] Create new configuration (${TARGET_MACHINE_TYPE})...\n" "${NEW_CONFIG_OPT}"

    if [ "$NON_INTERACTIVE" = "true" ]; then
      CONFIG_ID="${configs[0]}"
      CREATE_CONFIG=false
      log_step "Non-interactive: defaulting to first configuration '${CONFIG_ID}'."
    else
      while true; do
        printf "%bSelect an option [1-%d]: %b" "${BOLD}" "${NEW_CONFIG_OPT}" "${RESET}"
        read -r choice || choice=""
        choice="$(echo "${choice}" | tr -d ' ')"
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${NEW_CONFIG_OPT}" ]; then
          if [ "${choice}" -eq "${NEW_CONFIG_OPT}" ]; then
            CREATE_CONFIG=true
            CONFIG_ID="$(prompt_valid_id "Enter new configuration ID to create with high-performance ${TARGET_MACHINE_TYPE} specs" "ws-config")"
          else
            CREATE_CONFIG=false
            CONFIG_ID="${configs[$((choice - 1))]}"
          fi
          break
        else
          log_warn "Please enter a valid choice between 1 and ${NEW_CONFIG_OPT}."
        fi
      done
    fi
  fi
fi

if ! is_valid_id "${CONFIG_ID}"; then
  log_error "Config ID '${CONFIG_ID}' is invalid. Must match ^[a-z][a-z0-9-]{0,62}$."
  exit 1
fi
log_success "Target Configuration resolved: ${CONFIG_ID} (create_config=${CREATE_CONFIG})"

# ------------------------------------------------------------------------------
# 10. Workstation Naming & IAM Derivation
# ------------------------------------------------------------------------------
log_info "Deriving workstation name and IAM binding..."

DEFAULT_WS_ID="$(sanitize_email "${USER_EMAIL}")"
WORKSTATION_ID=""

if [ -n "${CLI_WORKSTATION_ID}" ]; then
  WORKSTATION_ID="${CLI_WORKSTATION_ID}"
  log_step "Workstation ID specified via CLI/env: ${WORKSTATION_ID}"
elif [ "$NON_INTERACTIVE" = "true" ]; then
  WORKSTATION_ID="${DEFAULT_WS_ID}"
  log_step "Non-interactive: using derived workstation ID '${WORKSTATION_ID}'"
else
  WORKSTATION_ID="$(prompt_valid_id "Enter workstation ID" "${DEFAULT_WS_ID}")"
fi

if ! is_valid_id "${WORKSTATION_ID}"; then
  log_error "Workstation ID '${WORKSTATION_ID}' is invalid. Must match ^[a-z][a-z0-9-]{0,62}$."
  exit 1
fi
log_success "Target Workstation resolved: ${WORKSTATION_ID} (User: ${USER_EMAIL})"

# ------------------------------------------------------------------------------
# 11. Configuration Summary & User Confirmation
# ------------------------------------------------------------------------------
printf "\n"
printf "%b================================================================================%b\n" "${CYAN}" "${RESET}"
printf "%b                    Deployment Configuration Summary                           %b\n" "${BOLD}" "${RESET}"
printf "%b================================================================================%b\n" "${CYAN}" "${RESET}"
printf "  %bProject ID:%b           %s\n" "${BOLD}" "${RESET}" "${PROJECT_ID}"
printf "  %bRegion:%b               %s\n" "${BOLD}" "${RESET}" "${REGION}"
printf "  %bCluster ID:%b           %s (%s)\n" "${BOLD}" "${RESET}" "${CLUSTER_ID}" "$([ "$CREATE_CLUSTER" = "true" ] && echo "create new" || echo "attach to existing")"
printf "  %bConfig ID:%b            %s (%s)\n" "${BOLD}" "${RESET}" "${CONFIG_ID}" "$([ "$CREATE_CONFIG" = "true" ] && echo "create new (${TARGET_MACHINE_TYPE}, 200GB pd-balanced)" || echo "attach to existing")"
printf "  %bWorkstation ID:%b       %s\n" "${BOLD}" "${RESET}" "${WORKSTATION_ID}"
printf "  %bIAM User Email:%b       %s (roles/workstations.user)\n" "${BOLD}" "${RESET}" "${USER_EMAIL}"
printf "  %bExecution Mode:%b       %s\n" "${BOLD}" "${RESET}" "$([ "$DRY_RUN" = "true" ] && echo "DRY-RUN (Simulated actions)" || echo "LIVE PROVISIONING")"
printf "%b================================================================================%b\n\n" "${CYAN}" "${RESET}"

if [ "$NON_INTERACTIVE" = "false" ] && [ "$DRY_RUN" = "false" ]; then
  if ! prompt_yes_no "Proceed with Terraform provisioning and workstation bootstrap?" "Y"; then
    log_warn "Setup cancelled by user."
    exit 0
  fi
fi

# ------------------------------------------------------------------------------
# 12. Dynamic terraform.tfvars Generation & Execution
# ------------------------------------------------------------------------------
log_info "Preparing Terraform variables..."

PROJECT_ID_ESC="$(escape_hcl_string "${PROJECT_ID}")"
REGION_ESC="$(escape_hcl_string "${REGION}")"
CLUSTER_ID_ESC="$(escape_hcl_string "${CLUSTER_ID}")"
CONFIG_ID_ESC="$(escape_hcl_string "${CONFIG_ID}")"
WORKSTATION_ID_ESC="$(escape_hcl_string "${WORKSTATION_ID}")"
USER_EMAIL_ESC="$(escape_hcl_string "${USER_EMAIL}")"

TFVARS_CONTENT="$(cat <<EOF
# ==============================================================================
# GCP Cloud Workstations Configuration
# Generated automatically by setup.sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ==============================================================================

# GCP Project and Region Settings
project_id = "${PROJECT_ID_ESC}"
region     = "${REGION_ESC}"

# Workstation Identifiers
cluster_id     = "${CLUSTER_ID_ESC}"
config_id      = "${CONFIG_ID_ESC}"
workstation_id = "${WORKSTATION_ID_ESC}"

# Workstation User IAM Binding
user_email = "${USER_EMAIL_ESC}"

# Resource Creation Toggles
create_cluster = ${CREATE_CLUSTER}
create_config  = ${CREATE_CONFIG}

# Network Settings (used when create_cluster = true)
network    = "default"
subnetwork = "default"

# Host Compute & Storage Specs
machine_type            = "${TARGET_MACHINE_TYPE}"
persistent_disk_size_gb = 200
persistent_disk_type    = "pd-balanced"
quick_start_pool_size   = 1

# Timeout Settings
idle_timeout    = "7200s"
running_timeout = "43200s"

# Container Image
container_image = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"

# Resource Labels
labels = {
  environment = "development"
  managed-by  = "terraform"
}
EOF
)"

if [ "$DRY_RUN" = "true" ]; then
  log_info "[DRY-RUN] Simulating terraform.tfvars generation:"
  printf "%b%s%b\n\n" "${DIM}" "${TFVARS_CONTENT}" "${RESET}"
  log_info "[DRY-RUN] Simulating: terraform init -input=false"
  log_info "[DRY-RUN] Simulating: terraform apply -auto-approve -input=false"
else
  log_info "Generating dynamic terraform.tfvars..."
  if [ -f "terraform.tfvars" ]; then
    BACKUP_FILE="terraform.tfvars.bak.$(date +%s)"
    cp "terraform.tfvars" "${BACKUP_FILE}"
    log_step "Existing terraform.tfvars backed up to ${BACKUP_FILE}"
  fi

  TMP_VARS="$(mktemp "${PWD}/.terraform.tfvars.tmp.XXXXXX")"
  printf "%s\n" "${TFVARS_CONTENT}" > "${TMP_VARS}"
  mv "${TMP_VARS}" "terraform.tfvars"
  TMP_VARS=""
  log_success "Generated terraform.tfvars successfully."

  log_info "Initializing Terraform..."
  terraform init -input=false

  log_info "Applying Terraform configuration..."
  terraform apply -auto-approve -input=false
  log_success "Terraform apply completed successfully."
fi

# ------------------------------------------------------------------------------
# 13. Workstation Start, State Polling & SSH Bootstrap
# ------------------------------------------------------------------------------
if [ "$DRY_RUN" = "true" ]; then
  log_info "[DRY-RUN] Simulating workstation startup:"
  log_step "gcloud workstations start \"${WORKSTATION_ID}\" --cluster=\"${CLUSTER_ID}\" --config=\"${CONFIG_ID}\" --region=\"${REGION}\""
  log_info "[DRY-RUN] Simulating workstation state polling (STATE_RUNNING)..."
  log_step "Polled gcloud workstations describe (simulated: STATE_RUNNING)"
  log_info "[DRY-RUN] Simulating bootstrap script push over SSH:"
  log_step "gcloud workstations ssh \"${WORKSTATION_ID}\" --cluster=\"${CLUSTER_ID}\" --config=\"${CONFIG_ID}\" --region=\"${REGION}\" --command=\"bash -s\" < scripts/workstation-init.sh"
else
  log_info "Starting workstation '${WORKSTATION_ID}'..."
  # If already started or starting, gcloud start returns 0 or informative message
  gcloud workstations start "${WORKSTATION_ID}" \
    --cluster="${CLUSTER_ID}" \
    --config="${CONFIG_ID}" \
    --region="${REGION}" 2>/dev/null || true

  log_info "Waiting for workstation '${WORKSTATION_ID}' to enter STATE_RUNNING (timeout: 300s)..."
  TIMEOUT_SECONDS=300
  START_TIME=$(date +%s)
  POLL_INTERVAL=5

  while true; do
    CURRENT_STATE="$(gcloud workstations describe "${WORKSTATION_ID}" \
      --cluster="${CLUSTER_ID}" \
      --config="${CONFIG_ID}" \
      --region="${REGION}" \
      --format="value(state)" 2>/dev/null || true)"

    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ "${CURRENT_STATE}" = "STATE_RUNNING" ]; then
      log_progress_done "Workstation '${WORKSTATION_ID}' is running (elapsed: ${ELAPSED}s)."
      break
    fi

    if [ "${CURRENT_STATE}" = "STATE_ERROR" ]; then
      printf "\n"
      log_error "Workstation '${WORKSTATION_ID}' entered STATE_ERROR."
      exit 1
    fi

    if [ ${ELAPSED} -ge ${TIMEOUT_SECONDS} ]; then
      printf "\n"
      log_error "Timed out after ${TIMEOUT_SECONDS}s waiting for workstation '${WORKSTATION_ID}' to reach STATE_RUNNING (last state: '${CURRENT_STATE:-UNKNOWN}')."
      exit 1
    fi

    log_progress "Waiting for workstation '${WORKSTATION_ID}' to enter STATE_RUNNING (current: ${CURRENT_STATE:-STARTING}, elapsed: ${ELAPSED}s)..."
    sleep ${POLL_INTERVAL}
  done

  # Synchronize local Application Default Credentials (ADC) to workstation
  LOCAL_ADC_FILE="${HOME}/.config/gcloud/application_default_credentials.json"
  if [ -f "${LOCAL_ADC_FILE}" ]; then
    LOCAL_ACTIVE_ACCOUNT="$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n 1 || true)"
    if [ -z "${LOCAL_ACTIVE_ACCOUNT}" ]; then
      LOCAL_ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
    fi
    LOCAL_ACTIVE_ACCOUNT="$(echo "${LOCAL_ACTIVE_ACCOUNT}" | tr -d ' ')"

    if [ -n "${LOCAL_ACTIVE_ACCOUNT}" ] && [ "${LOCAL_ACTIVE_ACCOUNT}" = "${USER_EMAIL}" ]; then
      log_info "Active local gcloud account matches workstation user (${USER_EMAIL}). Synchronizing ADC..."
      ADC_JSON="$(cat "${LOCAL_ADC_FILE}")"
      if gcloud workstations ssh "${WORKSTATION_ID}" \
        --cluster="${CLUSTER_ID}" \
        --config="${CONFIG_ID}" \
        --region="${REGION}" \
        --command="mkdir -p ~/.config/gcloud && chmod 700 ~/.config/gcloud && cat > ~/.config/gcloud/application_default_credentials.json && chmod 600 ~/.config/gcloud/application_default_credentials.json" <<< "${ADC_JSON}" 2>/dev/null; then
        log_step "Application Default Credentials synchronized to /home/user/.config/gcloud/application_default_credentials.json"
      else
        log_warn "Could not pre-sync ADC file over SSH. Workstation will use standard login instructions."
      fi
    else
      log_warn "Active local gcloud account ('${LOCAL_ACTIVE_ACCOUNT:-none}') does not match target workstation user ('${USER_EMAIL}')."
      log_warn "Skipping Application Default Credentials sync to prevent credential leakage and privilege escalation."
      log_info "The workstation user (${USER_EMAIL}) should authenticate inside the workstation using 'gcloud auth application-default login'."
    fi
  fi

  log_info "Pushing bootstrap provisioner script over SSH to '${WORKSTATION_ID}'..."
  gcloud workstations ssh "${WORKSTATION_ID}" \
    --cluster="${CLUSTER_ID}" \
    --config="${CONFIG_ID}" \
    --region="${REGION}" \
    --command="export WORKSTATION_ID='${WORKSTATION_ID}' CLUSTER_ID='${CLUSTER_ID}' CONFIG_ID='${CONFIG_ID}' REGION='${REGION}' GCP_PROJECT_ID='${PROJECT_ID}' USER_EMAIL='${USER_EMAIL}'; bash -s" < scripts/workstation-init.sh
  log_success "Workstation bootstrap script completed successfully."
fi

# ------------------------------------------------------------------------------
# 14. Handoff Summary Card
# ------------------------------------------------------------------------------
log_info "Extracting workstation connection endpoints..."

WORKSTATION_URL=""
if [ "$DRY_RUN" = "false" ]; then
  WORKSTATION_URL="$(terraform output -raw workstation_url 2>/dev/null || true)"
  if [ -z "${WORKSTATION_URL}" ] || [ "${WORKSTATION_URL}" = "null" ]; then
    HOST="$(gcloud workstations describe "${WORKSTATION_ID}" \
      --cluster="${CLUSTER_ID}" \
      --config="${CONFIG_ID}" \
      --region="${REGION}" \
      --format="value(host)" 2>/dev/null || true)"
    if [ -n "${HOST}" ]; then
      if [[ "${HOST}" == https://* ]]; then
        WORKSTATION_URL="${HOST}"
      else
        WORKSTATION_URL="https://${HOST}"
      fi
    fi
  fi
fi

if [ -z "${WORKSTATION_URL}" ] || [ "${WORKSTATION_URL}" = "null" ]; then
  WORKSTATION_URL="https://${WORKSTATION_ID}.${CLUSTER_ID}.${REGION}.workstations.cloud.google"
fi

SSH_CMD="gcloud workstations ssh ${WORKSTATION_ID} --cluster=${CLUSTER_ID} --config=${CONFIG_ID} --region=${REGION}"

printf "\n"
printf "%b================================================================================%b\n" "${GREEN}${BOLD}" "${RESET}"
printf "%b       🎉 Google Cloud Workstation Provisioned & Ready for Development!        %b\n" "${GREEN}${BOLD}" "${RESET}"
printf "%b================================================================================%b\n" "${GREEN}${BOLD}" "${RESET}"
printf "  %bWorkstation ID:%b     %s\n" "${BOLD}" "${RESET}" "${WORKSTATION_ID}"
printf "  %bCluster ID:%b         %s\n" "${BOLD}" "${RESET}" "${CLUSTER_ID}"
printf "  %bConfig ID:%b          %s\n" "${BOLD}" "${RESET}" "${CONFIG_ID}"
printf "  %bRegion:%b             %s\n" "${BOLD}" "${RESET}" "${REGION}"
printf "  %bGCP Project:%b        %s\n" "${BOLD}" "${RESET}" "${PROJECT_ID}"
printf "  %bUser Account:%b       %s\n" "${BOLD}" "${RESET}" "${USER_EMAIL}"
printf "  %bQuota Project:%b      %s (Synced to ADC)\n" "${BOLD}" "${RESET}" "${PROJECT_ID}"
printf "\n"
printf "  %b🌐 Browser IDE Web Interface:%b\n" "${CYAN}${BOLD}" "${RESET}"
printf "     %b%s%b\n" "${BLUE}${BOLD}" "${WORKSTATION_URL}" "${RESET}"
printf "\n"
printf "  %b💻 Terminal SSH Access:%b\n" "${YELLOW}${BOLD}" "${RESET}"
printf "     %b%s%b\n" "${BOLD}" "${SSH_CMD}" "${RESET}"
printf "\n"
printf "  %b🚀 Next Steps:%b\n" "${MAGENTA}${BOLD}" "${RESET}"
printf "     1. Access your workstation via the Browser IDE or SSH command above.\n"
printf "     2. Type 'motd' to view installed toolchains, versions, and paths.\n"
printf "     3. Verify workstation auth: 'gcloud auth application-default print-access-token'\n"
printf "     4. Run 'agy auth login' to authenticate Google Antigravity.\n"
printf "     5. Run 'claude' to begin pair programming (pre-configured for Vertex AI).\n"
printf "%b================================================================================%b\n\n" "${GREEN}${BOLD}" "${RESET}"

log_success "All workstation automation tasks completed successfully!"
exit 0
