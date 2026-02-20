#!/usr/bin/env bash
# =============================================================================
# setup_hdfs.sh — Idempotent HDFS directory setup for hadoopuser project
# =============================================================================
# 1) Waits for HDFS to be ready
# 2) Creates /user/hadoopuser/project/{logs,db_data,input,output}
# 3) Sets permissions 755
# 4) Verifies creation
# Safe to run multiple times (idempotent).
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly BASE_DIR="/user/hadoopuser/project"
readonly SUBDIRS=(logs db_data input output)
readonly PERMS="755"
readonly MAX_WAIT_ATTEMPTS="${HDFS_WAIT_ATTEMPTS:-60}"
readonly WAIT_INTERVAL="${HDFS_WAIT_INTERVAL:-5}"

# Log to file (local path; HDFS logs dir may not exist yet)
LOG_DIR="${LOG_DIR:-/project}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/setup_hdfs.log}"
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
  LOG_FILE="/tmp/setup_hdfs.log"
fi
readonly LOG_DIR LOG_FILE

# -----------------------------------------------------------------------------
# Colored output (only when stdout is a TTY)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# -----------------------------------------------------------------------------
# Logging: write to log file and optionally echo with color
# -----------------------------------------------------------------------------

log() {
  local level="$1"
  shift
  local msg="$*"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "${ts} [${level}] ${msg}" >> "$LOG_FILE"
}

log_info() {
  log "INFO" "$*"
  echo -e "${CYAN}[INFO]${NC} $*"
}

log_ok() {
  log "OK" "$*"
  echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
  log "WARN" "$*"
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_err() {
  log "ERROR" "$*"
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# -----------------------------------------------------------------------------
# HDFS command: prefer hdfs dfs, fall back to hadoop fs
# -----------------------------------------------------------------------------
hdfs_cmd() {
  if command -v hdfs &>/dev/null; then
    hdfs dfs "$@"
  elif command -v hadoop &>/dev/null; then
    hadoop fs "$@"
  else
    log_err "Neither 'hdfs' nor 'hadoop' found in PATH."
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Wait for HDFS to be ready (idempotent: safe to call every run)
# -----------------------------------------------------------------------------
wait_for_hdfs() {
  log_info "Waiting for HDFS (max ${MAX_WAIT_ATTEMPTS} attempts, ${WAIT_INTERVAL}s apart) ..."
  local attempt=1
  while [[ $attempt -le $MAX_WAIT_ATTEMPTS ]]; do
    if hdfs_cmd -ls / &>/dev/null; then
      log_ok "HDFS is ready (attempt $attempt)."
      return 0
    fi
    log "INFO" "HDFS not ready, attempt $attempt/$MAX_WAIT_ATTEMPTS"
    echo -ne "${YELLOW}  Attempt $attempt/$MAX_WAIT_ATTEMPTS ...${NC}\r"
    sleep "$WAIT_INTERVAL"
    ((attempt++)) || true
  done
  log_err "HDFS did not become ready after $MAX_WAIT_ATTEMPTS attempts."
  return 1
}

# -----------------------------------------------------------------------------
# Create directory tree and set permissions (idempotent)
# -----------------------------------------------------------------------------
create_dirs() {
  log_info "Creating base directory: $BASE_DIR"
  hdfs_cmd -mkdir -p "$BASE_DIR" || {
    log_err "Failed to create base directory: $BASE_DIR"
    return 1
  }

  for sub in "${SUBDIRS[@]}"; do
    local path="${BASE_DIR}/${sub}"
    log_info "Creating: $path"
    hdfs_cmd -mkdir -p "$path" || {
      log_err "Failed to create: $path"
      return 1
    }
  done

  log_info "Setting permissions $PERMS on $BASE_DIR (recursive)"
  hdfs_cmd -chmod -R "$PERMS" "$BASE_DIR" || {
    log_err "Failed to chmod $PERMS on $BASE_DIR"
    return 1
  }
  log_ok "Directories created and permissions set."
}

# -----------------------------------------------------------------------------
# Verify all directories exist and have correct permissions
# -----------------------------------------------------------------------------
verify_dirs() {
  log_info "Verifying directory structure ..."
  local failed=0
  local listing
  listing=$(hdfs_cmd -ls -R "$BASE_DIR" 2>&1) || {
    log_err "Failed to list $BASE_DIR"
    return 1
  }

  for sub in "${SUBDIRS[@]}"; do
    local path="${BASE_DIR}/${sub}"
    if hdfs_cmd -test -d "$path" 2>/dev/null; then
      log_ok "  $path exists."
    else
      log_err "  $path missing or not a directory."
      ((failed++)) || true
    fi
  done

  if [[ $failed -gt 0 ]]; then
    log_err "Verification failed: $failed directory(ies) missing."
    return 1
  fi
  log_ok "Verification passed. Listing:"
  echo "$listing" | while read -r line; do echo "    $line"; done || true
  return 0
}

# -----------------------------------------------------------------------------
# Error handler
# -----------------------------------------------------------------------------
cleanup_on_err() {
  log_err "Script failed. Check log: $LOG_FILE"
  exit 1
}
trap cleanup_on_err ERR

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  log "INFO" "=== $SCRIPT_NAME started ==="
  echo -e "${CYAN}=== $SCRIPT_NAME ===${NC}"

  wait_for_hdfs
  create_dirs
  verify_dirs

  log "INFO" "=== $SCRIPT_NAME finished successfully ==="
  echo -e "${GREEN}=== $SCRIPT_NAME finished successfully ===${NC}"
  exit 0
}

main "$@"
