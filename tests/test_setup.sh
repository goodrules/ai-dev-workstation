#!/usr/bin/env bash
# ==============================================================================
# Automated Test Suite for setup.sh (Slice 3)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_SCRIPT="${REPO_ROOT}/setup.sh"

PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
  local test_name="$1"
  shift
  printf "Running test: %-60s " "${test_name}..."
  if "$@"; then
    printf "[PASSED]\n"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    printf "[FAILED]\n"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# 1. Syntax Check with bash -n
test_bash_syntax() {
  bash -n "${SETUP_SCRIPT}"
}

# 2. Syntax Check with zsh -n
test_zsh_syntax() {
  if command -v zsh >/dev/null 2>&1; then
    zsh -n "${SETUP_SCRIPT}"
  else
    return 0
  fi
}

# 3. Help Flag
test_help_flag() {
  local output
  output="$("${SETUP_SCRIPT}" --help)"
  echo "${output}" | grep -q "Usage: ./setup.sh" && \
  echo "${output}" | grep -q -- "--region" && \
  echo "${output}" | grep -q -- "--dry-run"
}

# 4. Unknown Flag Rejection
test_unknown_flag() {
  local output
  if output="$("${SETUP_SCRIPT}" --non-existent-option 2>&1)"; then
    return 1
  else
    echo "${output}" | grep -q "Unknown option"
  fi
}

# 5. Pre-flight Check: Missing gcloud
test_missing_gcloud() {
  local output
  if output="$(PATH="/usr/bin:/bin" "${SETUP_SCRIPT}" 2>&1)"; then
    return 1
  else
    echo "${output}" | grep -q "gcloud.*CLI is not installed" && \
    echo "${output}" | grep -q "brew install --cask google-cloud-sdk"
  fi
}

# 6. Pre-flight Check: Missing terraform
test_missing_terraform() {
  local gcloud_dir
  gcloud_dir="$(dirname "$(which gcloud)")"
  local output
  if output="$(PATH="${gcloud_dir}:/usr/bin:/bin" "${SETUP_SCRIPT}" 2>&1)"; then
    return 1
  else
    echo "${output}" | grep -q "terraform.*CLI is not installed" && \
    echo "${output}" | grep -q "brew install hashicorp/tap/terraform"
  fi
}

# 7. Non-interactive Dry Run Execution
test_dry_run_non_interactive() {
  local output
  output="$("${SETUP_SCRIPT}" --dry-run --non-interactive)"
  echo "${output}" | grep -q "DRY-RUN MODE ENABLED" && \
  echo "${output}" | grep -q "Target Cluster resolved" && \
  echo "${output}" | grep -q "Target Configuration resolved" && \
  echo "${output}" | grep -q "Target Workstation resolved" && \
  echo "${output}" | grep -q "Browser IDE Web Interface" && \
  echo "${output}" | grep -q "All workstation automation tasks completed successfully"
}

# 8. Flag Overrides in Dry Run
test_flag_overrides() {
  local output
  output="$("${SETUP_SCRIPT}" --dry-run --non-interactive \
    --region us-east4 \
    --project test-override-proj \
    --email test.dev@example.com \
    --cluster custom-cls \
    --config custom-cfg \
    --workstation custom-ws)"
  echo "${output}" | grep -q 'project_id = "test-override-proj"' && \
  echo "${output}" | grep -q 'region     = "us-east4"' && \
  echo "${output}" | grep -q 'cluster_id     = "custom-cls"' && \
  echo "${output}" | grep -q 'config_id      = "custom-cfg"' && \
  echo "${output}" | grep -q 'workstation_id = "custom-ws"' && \
  echo "${output}" | grep -q 'user_email = "test.dev@example.com"'
}

# 9. Email Sanitization (Derived Name: ws-alex-smith)
test_email_sanitization() {
  local output
  output="$("${SETUP_SCRIPT}" --dry-run --non-interactive \
    --email alex.smith@example.com \
    --cluster custom-cls \
    --config custom-cfg)"
  echo "${output}" | grep -q 'workstation_id = "ws-alex-smith"'
}

# 10. Invalid Email Rejection
test_invalid_email() {
  local output
  if output="$("${SETUP_SCRIPT}" --dry-run --non-interactive --email "notanemail" 2>&1)"; then
    return 1
  else
    echo "${output}" | grep -q "is not a valid email address"
  fi
}

# 11. Invalid Workstation ID Rejection
test_invalid_workstation_id() {
  local output
  if output="$("${SETUP_SCRIPT}" --dry-run --non-interactive --workstation "123-INVALID_ID" 2>&1)"; then
    return 1
  else
    echo "${output}" | grep -q "is invalid"
  fi
}

# 12. Multiple Clusters Selection in Menu
test_multiple_clusters_menu() {
  local output
  output="$(printf "y\ny\n2\ny\n\ny\n" | MOCK_CLUSTERS="alpha-cls,beta-cls" "${SETUP_SCRIPT}" --dry-run 2>&1)"
  echo "${output}" | grep -q 'cluster_id     = "beta-cls"' && \
  echo "${output}" | grep -q 'create_cluster = false'
}

# 13. Multiple Configs Selection in Menu
test_multiple_configs_menu() {
  local output
  output="$(printf "y\ny\ny\n2\n\ny\n" | MOCK_CONFIGS="cfg-one,cfg-two" "${SETUP_SCRIPT}" --dry-run 2>&1)"
  echo "${output}" | grep -q 'config_id      = "cfg-two"' && \
  echo "${output}" | grep -q 'create_config  = false'
}

# 14. macOS /bin/bash Compatibility
test_macos_bash() {
  /bin/bash "${SETUP_SCRIPT}" --dry-run --non-interactive >/dev/null
}

# 15. macOS /bin/zsh Compatibility
test_macos_zsh() {
  /bin/zsh "${SETUP_SCRIPT}" --dry-run --non-interactive >/dev/null
}

# 16. Environment Variable Ingestion (CLUSTER_ID, CONFIG_ID, WORKSTATION_ID)
test_env_vars() {
  local output
  output="$(CLUSTER_ID="custom-cls-env" CONFIG_ID="custom-cfg-env" WORKSTATION_ID="custom-ws-env" "${SETUP_SCRIPT}" --dry-run --non-interactive)"
  echo "${output}" | grep -q 'cluster_id     = "custom-cls-env"' && \
  echo "${output}" | grep -q 'config_id      = "custom-cfg-env"' && \
  echo "${output}" | grep -q 'workstation_id = "custom-ws-env"'
}

# 17. Workstation Init Provisioner Syntax (bash -n & zsh -n)
test_workstation_init_syntax() {
  bash -n "${REPO_ROOT}/scripts/workstation-init.sh"
  if command -v zsh >/dev/null 2>&1; then
    zsh -n "${REPO_ROOT}/scripts/workstation-init.sh"
  fi
}

# 18. Security Hardening: Pin TLS 1.2 and HTTPS in curl installers
test_hardened_curl_protocols() {
  local unhardened
  unhardened="$(grep -n 'curl ' "${REPO_ROOT}/scripts/workstation-init.sh" | grep -v '^[[:space:]]*#' | grep -v "\-\-proto '=https' \-\-tlsv1\.2" || true)"
  [ -z "${unhardened}" ]
}

# 19. Security Hardening: Zero direct curl-to-shell pipes
test_no_direct_curl_pipes() {
  local piped
  piped="$(grep -E 'curl.*\|[[:space:]]*(bash|sh)' "${REPO_ROOT}/scripts/workstation-init.sh" | grep -v '^[[:space:]]*#' || true)"
  [ -z "${piped}" ]
}

# 20. Security Hardening: Host Credential Sync Check in setup.sh
test_host_credential_sync_check() {
  grep -q 'LOCAL_ACTIVE_ACCOUNT=' "${SETUP_SCRIPT}" && \
  grep -q 'LOCAL_ACTIVE_ACCOUNT}" = "${USER_EMAIL}"' "${SETUP_SCRIPT}" && \
  grep -q 'Skipping Application Default Credentials sync to prevent credential leakage' "${SETUP_SCRIPT}"
}

echo "========================================================================"
echo " Running Automated Test Suite for setup.sh"
echo "========================================================================"

run_test "1. Bash syntax check (bash -n)" test_bash_syntax
run_test "2. Zsh syntax check (zsh -n)" test_zsh_syntax
run_test "3. Help flag (--help)" test_help_flag
run_test "4. Unknown flag rejection" test_unknown_flag
run_test "5. Pre-flight check: Missing gcloud" test_missing_gcloud
run_test "6. Pre-flight check: Missing terraform" test_missing_terraform
run_test "7. Non-interactive dry-run execution" test_dry_run_non_interactive
run_test "8. CLI flag overrides in dry-run" test_flag_overrides
run_test "9. Workstation ID derivation from email" test_email_sanitization
run_test "10. Invalid email format rejection" test_invalid_email
run_test "11. Invalid workstation ID rejection" test_invalid_workstation_id
run_test "12. Multiple clusters menu selection" test_multiple_clusters_menu
run_test "13. Multiple configs menu selection" test_multiple_configs_menu
run_test "14. Native macOS /bin/bash execution" test_macos_bash
run_test "15. Native macOS /bin/zsh execution" test_macos_zsh
run_test "16. Environment variable ingestion" test_env_vars
run_test "17. Workstation bootstrap syntax (bash & zsh)" test_workstation_init_syntax
run_test "18. Hardened TLS 1.2 protocol in curl installers" test_hardened_curl_protocols
run_test "19. Decoupled curl installer pipelines (no curl | bash)" test_no_direct_curl_pipes
run_test "20. Host credential sync security verification" test_host_credential_sync_check

echo "========================================================================"
echo " Test Results: ${PASSED_TESTS} Passed, ${FAILED_TESTS} Failed"
echo "========================================================================"

if [ ${FAILED_TESTS} -ne 0 ]; then
  exit 1
fi
exit 0
