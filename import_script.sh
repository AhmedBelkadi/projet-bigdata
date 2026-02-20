#!/usr/bin/env bash
# =============================================================================
# import_script.sh — Sqoop import from MySQL ecommerce_db to HDFS
# =============================================================================
# 1) customers: WHERE status='ACTIVE', 3 mappers, pipe '|',
#    target /user/hadoopuser/project/db_data/customers/
# 2) orders: WHERE order_date >= '2024-01-01' AND status='...', 2 mappers,
#    comma separator, target /user/hadoopuser/project/db_data/orders/
#    (default status=DELIVERED; set ORDERS_STATUS=completed for schema with completed)
# Includes MySQL connectivity check, error handling, and HDFS verification.
# MySQL: host=mysql, user=root, password=rootpassword (overridable via env).
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration — MySQL and HDFS paths
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly MYSQL_HOST="${MYSQL_HOST:-mysql}"
readonly MYSQL_PORT="${MYSQL_PORT:-3306}"
readonly MYSQL_USER="${MYSQL_USER:-root}"
readonly MYSQL_PASSWORD="${MYSQL_PASSWORD:-rootpassword}"
readonly MYSQL_DATABASE="${MYSQL_DATABASE:-ecommerce_db}"
readonly JDBC_URL="jdbc:mysql://${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"

readonly CUSTOMERS_TARGET="/user/hadoopuser/project/db_data/customers"
readonly ORDERS_TARGET="/user/hadoopuser/project/db_data/orders"
# Orders filter: sample_data.sql uses 'DELIVERED'; set ORDERS_STATUS=completed if your schema uses it
readonly ORDERS_STATUS="${ORDERS_STATUS:-DELIVERED}"

# Log file
LOG_DIR="${LOG_DIR:-/project}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/import_script.log}"
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
  LOG_FILE="/tmp/import_script.log"
fi
readonly LOG_DIR LOG_FILE

# -----------------------------------------------------------------------------
# Colored output
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

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $*" >> "$LOG_FILE"; }
log_info() { log "INFO" "$*"; echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { log "OK" "$*";   echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { log "WARN" "$*"; echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { log "ERROR" "$*"; echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# MySQL connectivity check
# -----------------------------------------------------------------------------
check_mysql() {
  log_info "Checking MySQL at ${MYSQL_HOST}:${MYSQL_PORT} (database: ${MYSQL_DATABASE}) ..."
  if command -v mysql &>/dev/null; then
    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        -e "SELECT 1 FROM DUAL;" "$MYSQL_DATABASE" &>/dev/null; then
      log_ok "MySQL connection successful."
      return 0
    fi
  fi
  # Fallback: try Sqoop list-tables as connectivity test
  log_warn "mysql client not found or connection failed; trying Sqoop list-tables ..."
  if sqoop list-tables --connect "$JDBC_URL" --username "$MYSQL_USER" --password "$MYSQL_PASSWORD" &>/dev/null; then
    log_ok "Sqoop can connect to MySQL."
    return 0
  fi
  log_err "Cannot connect to MySQL. Check host, port, user, password, and database."
  return 1
}

# -----------------------------------------------------------------------------
# HDFS command (hdfs dfs or hadoop fs)
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
# Verify HDFS path exists and has part files; print line count
# -----------------------------------------------------------------------------
verify_hdfs_dir() {
  local dir="$1"
  local label="$2"
  log_info "Verifying $label: $dir"
  if ! hdfs_cmd -test -d "$dir" 2>/dev/null; then
    log_err "HDFS path does not exist or is not a directory: $dir"
    return 1
  fi
  local count
  count=$(hdfs_cmd -ls "$dir" 2>/dev/null | grep -c "part-" || true)
  if [[ "${count:-0}" -eq 0 ]]; then
    log_warn "No part files found under $dir"
    return 1
  fi
  log_ok "  $dir: $count part file(s)"
  local lines
  lines=$(hdfs_cmd -cat "$dir/part-*" 2>/dev/null | wc -l || echo "0")
  log_ok "  Approximate line count: $lines"
  return 0
}

# -----------------------------------------------------------------------------
# Sqoop import: customers (ACTIVE, 3 mappers, pipe separator)
# -----------------------------------------------------------------------------
import_customers() {
  log_info "Sqoop import: customers (status='ACTIVE') -> $CUSTOMERS_TARGET"
  # Remove target dir so import is idempotent (Sqoop fails if dir exists by default)
  hdfs_cmd -rm -r -f "$CUSTOMERS_TARGET" 2>/dev/null || true
  if ! sqoop import \
    -D mapreduce.framework.name=yarn \
    --connect "$JDBC_URL" \
    --username "$MYSQL_USER" \
    --password "$MYSQL_PASSWORD" \
    --table customers \
    --where "status='ACTIVE'" \
    --target-dir "$CUSTOMERS_TARGET" \
    --num-mappers 3 \
    --fields-terminated-by '|' \
    --split-by customer_id; then
    log_err "Sqoop import failed: customers"
    return 1
  fi
  log_ok "Sqoop import completed: customers"
  return 0
}

# -----------------------------------------------------------------------------
# Sqoop import: orders (order_date >= '2024-01-01' AND status=ORDERS_STATUS,
# 2 mappers, comma separator)
# Default ORDERS_STATUS=DELIVERED (sample_data.sql); set ORDERS_STATUS=completed if needed.
# -----------------------------------------------------------------------------
import_orders() {
  log_info "Sqoop import: orders (order_date >= '2024-01-01' AND status='${ORDERS_STATUS}') -> $ORDERS_TARGET"
  hdfs_cmd -rm -r -f "$ORDERS_TARGET" 2>/dev/null || true
  if ! sqoop import \
    -D mapreduce.framework.name=yarn \
    --connect "$JDBC_URL" \
    --username "$MYSQL_USER" \
    --password "$MYSQL_PASSWORD" \
    --table orders \
    --where "order_date >= '2024-01-01' AND status='${ORDERS_STATUS}'" \
    --target-dir "$ORDERS_TARGET" \
    --num-mappers 2 \
    --fields-terminated-by ',' \
    --split-by order_id; then
    log_err "Sqoop import failed: orders"
    return 1
  fi
  log_ok "Sqoop import completed: orders"
  return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  log "INFO" "=== $SCRIPT_NAME started ==="
  echo -e "${CYAN}=== $SCRIPT_NAME ===${NC}"

  check_mysql || exit 1
  import_customers || exit 1
  import_orders    || exit 1

  log_info "Verification:"
  verify_hdfs_dir "$CUSTOMERS_TARGET" "customers" || true
  verify_hdfs_dir "$ORDERS_TARGET" "orders" || true

  log "INFO" "=== $SCRIPT_NAME finished successfully ==="
  echo -e "${GREEN}=== $SCRIPT_NAME finished successfully ===${NC}"
  exit 0
}

trap 'log_err "Script failed. Check log: $LOG_FILE"; exit 1' ERR
main "$@"
