#!/usr/bin/env bash
set -euo pipefail

APP_ID="jebgalgnebhfojomionfpkfelancnnkf"
EXPECTED_CRX_SHA256="6315ac809037997a028b0c6fd7af959fc7967651a3b7f800044c613f48365ffd"

RUN_SERVER=false
SKIP_PKG=false
SKIP_DOWNLOAD=false
REDIRECT_GOOGLE=false

usage() {
  cat <<'EOF'
Usage: scripts/setup-termux.sh [options]

Options:
  --run            Start the local updater after setup.
  --skip-pkg       Skip package installation.
  --skip-download  Skip go mod download.
  --redirect-google
                   Redirect unknown Chromium components to Google.
  -h, --help       Show this help.

Environment:
  GO_UPDATE_ADDR   Listen address. Defaults to 127.0.0.1:8000.
  GO_UPDATE_HOST   Host used when GO_UPDATE_ADDR is not set. Defaults to 127.0.0.1.
  GO_UPDATE_PORT   Port used when GO_UPDATE_ADDR is not set. Defaults to 8000.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      RUN_SERVER=true
      ;;
    --skip-pkg)
      SKIP_PKG=true
      ;;
    --skip-download)
      SKIP_DOWNLOAD=true
      ;;
    --redirect-google)
      REDIRECT_GOOGLE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '[setup-termux] %s\n' "$*"
}

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

ROOT_DIR="$(repo_root)"
CRX_PATH="${ROOT_DIR}/local_crx/${APP_ID}/extension_1_0_0.crx"

install_packages() {
  if "${SKIP_PKG}"; then
    log "Skipping package installation."
    return
  fi

  if command -v pkg >/dev/null 2>&1; then
    log "Installing Termux packages: git golang ca-certificates coreutils"
    pkg update -y
    pkg install -y git golang ca-certificates coreutils
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing apt packages: git golang-go ca-certificates coreutils"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      git golang-go ca-certificates coreutils
    return
  fi

  if command -v apt >/dev/null 2>&1; then
    log "Installing apt packages: git golang-go ca-certificates coreutils"
    apt update
    apt install -y git golang-go ca-certificates coreutils
    return
  fi

  log "No supported package manager found; skipping package installation."
}

verify_toolchain() {
  if ! command -v go >/dev/null 2>&1; then
    echo "go was not found. Install it with one of:" >&2
    echo "  pkg install golang" >&2
    echo "  apt install golang-go" >&2
    exit 1
  fi

  if ! command -v gofmt >/dev/null 2>&1; then
    echo "gofmt was not found. Install it with one of:" >&2
    echo "  pkg install golang" >&2
    echo "  apt install golang-go" >&2
    exit 1
  fi

  log "$(go version)"
}

verify_crx() {
  if [[ ! -f "${CRX_PATH}" ]]; then
    echo "Missing local CRX: ${CRX_PATH}" >&2
    exit 1
  fi

  local actual_sha256
  actual_sha256="$(sha256sum "${CRX_PATH}" | awk '{print $1}')"
  if [[ "${actual_sha256}" != "${EXPECTED_CRX_SHA256}" ]]; then
    echo "CRX hash mismatch: ${CRX_PATH}" >&2
    echo "  expected: ${EXPECTED_CRX_SHA256}" >&2
    echo "  actual:   ${actual_sha256}" >&2
    exit 1
  fi

  log "Verified local CRX: ${CRX_PATH}"
}

download_modules() {
  if "${SKIP_DOWNLOAD}"; then
    log "Skipping go mod download."
    return
  fi

  log "Downloading Go modules."
  (cd "${ROOT_DIR}" && GOTOOLCHAIN=local go mod download)
}

default_addr() {
  if [[ -n "${GO_UPDATE_ADDR:-}" ]]; then
    printf '%s\n' "${GO_UPDATE_ADDR}"
    return
  fi

  printf '%s:%s\n' "${GO_UPDATE_HOST:-127.0.0.1}" "${GO_UPDATE_PORT:-8000}"
}

redirect_unknown_applications() {
  if "${REDIRECT_GOOGLE}"; then
    printf 'true\n'
    return
  fi

  printf 'false\n'
}

component_updater_host() {
  if "${REDIRECT_GOOGLE}"; then
    printf '%s\n' "${COMPONENT_UPDATER_HOST:-update.googleapis.com}"
    return
  fi

  printf '%s\n' "${COMPONENT_UPDATER_HOST:-componentupdater.brave.com}"
}

updater_redirect_scheme() {
  printf '%s\n' "${UPDATER_REDIRECT_SCHEME:-https}"
}

base_url_for_addr() {
  local addr="$1"
  if [[ -n "${S3_EXTENSIONS_BUCKET_URL:-}" ]]; then
    printf '%s\n' "${S3_EXTENSIONS_BUCKET_URL}"
    return
  fi

  if [[ "${addr}" == :* ]]; then
    printf 'http://127.0.0.1%s\n' "${addr}"
    return
  fi

  printf 'http://%s\n' "${addr}"
}

print_run_command() {
  local addr="$1"
  local base_url="$2"
  local redirect_unknown="$3"
  local component_host="$4"
  local redirect_scheme="$5"

  cat <<EOF

Run the local updater:

  cd "${ROOT_DIR}"
  GO_UPDATE_ADDR=${addr} \\
  GO_UPDATE_USE_STATIC_EXTENSIONS=true \\
  LOCAL_CRX_DIR=\$PWD/local_crx \\
  S3_EXTENSIONS_BUCKET_URL=${base_url} \\
  GO_UPDATE_REDIRECT_UNKNOWN_APPLICATIONS=${redirect_unknown} \\
  COMPONENT_UPDATER_HOST=${component_host} \\
  UPDATER_REDIRECT_SCHEME=${redirect_scheme} \\
  LOG_REQUEST=true \\
  GOTOOLCHAIN=local go run .

Client update URL:

  http://127.0.0.1:${addr##*:}/update2/json

EOF
}

run_server() {
  local addr="$1"
  local base_url="$2"
  local redirect_unknown="$3"
  local component_host="$4"
  local redirect_scheme="$5"

  log "Starting local updater on ${addr}"
  cd "${ROOT_DIR}"
  GO_UPDATE_ADDR="${addr}" \
  GO_UPDATE_USE_STATIC_EXTENSIONS=true \
  LOCAL_CRX_DIR="${ROOT_DIR}/local_crx" \
  S3_EXTENSIONS_BUCKET_URL="${base_url}" \
  GO_UPDATE_REDIRECT_UNKNOWN_APPLICATIONS="${redirect_unknown}" \
  COMPONENT_UPDATER_HOST="${component_host}" \
  UPDATER_REDIRECT_SCHEME="${redirect_scheme}" \
  LOG_REQUEST=true \
  GOTOOLCHAIN=local go run .
}

main() {
  install_packages
  verify_toolchain
  verify_crx
  download_modules

  local addr
  local base_url
  local redirect_unknown
  local component_host
  local redirect_scheme
  addr="$(default_addr)"
  base_url="$(base_url_for_addr "${addr}")"
  redirect_unknown="$(redirect_unknown_applications)"
  component_host="$(component_updater_host)"
  redirect_scheme="$(updater_redirect_scheme)"

  print_run_command "${addr}" "${base_url}" \
    "${redirect_unknown}" "${component_host}" "${redirect_scheme}"

  if "${RUN_SERVER}"; then
    run_server "${addr}" "${base_url}" \
      "${redirect_unknown}" "${component_host}" "${redirect_scheme}"
  fi
}

main "$@"
