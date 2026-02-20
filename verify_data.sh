#!/usr/bin/env bash
# =============================================================================
# verify_data.sh — Comprehensive verification of HDFS, Flume, Sqoop, MapReduce, services
# =============================================================================
# 1) HDFS structure and file counts
# 2) Flume log files and samples
# 3) Sqoop imported data with record counts
# 4) MapReduce results
# 5) Service health (HDFS, YARN, MySQL)
# Color-coded: green=OK, yellow=warning, red=fail. Table format for samples.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly BASE_DIR="/user/hadoopuser/project"
readonly LOGS_DIR="${BASE_DIR}/logs"
readonly DB_DATA_DIR="${BASE_DIR}/db_data"
readonly CUSTOMERS_DIR="${DB_DATA_DIR}/customers"
readonly ORDERS_DIR="${DB_DATA_DIR}/orders"
readonly OUTPUT_DIR="${BASE_DIR}/output/log_analysis"
readonly MYSQL_HOST="${MYSQL_HOST:-mysql}"
readonly MYSQL_PORT="${MYSQL_PORT:-3306}"
readonly MYSQL_USER="${MYSQL_USER:-root}"
readonly MYSQL_PASSWORD="${MYSQL_PASSWORD:-rootpassword}"
readonly MYSQL_DATABASE="${MYSQL_DATABASE:-ecommerce_db}"
readonly RM_URL="${YARN_RM_URL:-http://resourcemanager:8088}"
readonly SAMPLE_LINES="${SAMPLE_LINES:-5}"

# -----------------------------------------------------------------------------
# Colors (only when stdout is TTY)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

status_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
status_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
status_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
section()      { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}"; }
subsection()   { echo -e "\n${DIM}--- $* ---${NC}"; }

# -----------------------------------------------------------------------------
# HDFS / Hadoop
# -----------------------------------------------------------------------------
hdfs_cmd() {
  if command -v hdfs &>/dev/null; then
    hdfs dfs "$@"
  elif command -v hadoop &>/dev/null; then
    hadoop fs "$@"
  else
    status_fail "Neither 'hdfs' nor 'hadoop' in PATH."
    exit 1
  fi
}

hdfs_dir_exists() {
  hdfs_cmd -test -d "$1" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 1) HDFS structure and file counts
# -----------------------------------------------------------------------------
verify_hdfs_structure() {
  section "1) HDFS structure and file counts"
  local fail=0

  subsection "Project base: $BASE_DIR"
  if hdfs_dir_exists "$BASE_DIR"; then
    status_ok "Base directory exists."
    hdfs_cmd -ls "$BASE_DIR" 2>/dev/null | while read -r line; do
      echo "  $line"
    done
  else
    status_fail "Base directory missing: $BASE_DIR"
    ((fail++)) || true
    return $fail
  fi

  subsection "Expected subdirectories and file counts"
  printf "  %-45s %-10s STATUS\n" "PATH" "FILES"
  printf "  %-45s %-10s ------\n" "---------------------------------------------" "----------"
  for sub in logs db_data input output; do
    local path="${BASE_DIR}/${sub}"
    local count=0
    if hdfs_dir_exists "$path"; then
      count=$(hdfs_cmd -ls -R "$path" 2>/dev/null | grep "^-" | wc -l)
    fi
    printf "  %-45s %-10s " "$path" "$count"
    if hdfs_dir_exists "$path"; then
      [[ "$count" -gt 0 ]] && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}empty${NC}"
    else
      echo -e "${RED}missing${NC}"
      ((fail++)) || true
    fi
  done
  return $fail
}

# -----------------------------------------------------------------------------
# 2) Flume log files and samples
# -----------------------------------------------------------------------------
verify_flume_logs() {
  section "2) Flume log files and samples"
  local fail=0
  local tmp
  tmp=$(mktemp)

  subsection "Log directory: $LOGS_DIR"
  if ! hdfs_dir_exists "$LOGS_DIR"; then
    status_fail "Logs directory missing."
    rm -f "$tmp"
    return 1
  fi
  local file_count
  file_count=$(hdfs_cmd -ls "$LOGS_DIR" 2>/dev/null | grep "^-" | wc -l)
  if [[ "$file_count" -eq 0 ]]; then
    status_warn "No log files found (Flume may not have run yet)."
    rm -f "$tmp"
    return 0
  fi
  status_ok "Found $file_count file(s)."

  subsection "File listing (name, size)"
  printf "  %-50s %s\n" "FILENAME" "SIZE"
  printf "  %-50s %s\n" "--------------------------------------------------" "----------"
  hdfs_cmd -ls "$LOGS_DIR" 2>/dev/null | while read -r _ _ _ _ size _ _ name; do
    [[ -n "$name" ]] && printf "  %-50s %s\n" "$(basename "$name")" "$size"
  done

  subsection "Sample log lines (first $SAMPLE_LINES lines from first file)"
  local first_file
  first_file=$(hdfs_cmd -ls "$LOGS_DIR" 2>/dev/null | grep "^-" | head -1 | awk '{print $8}')
  if [[ -n "$first_file" ]]; then
    hdfs_cmd -cat "$first_file" 2>/dev/null | head -n "$SAMPLE_LINES" > "$tmp" || true
    if [[ -s "$tmp" ]]; then
      printf "  %-80s\n" "LINE (truncated)"
      printf "  %-80s\n" "--------------------------------------------------------------------------------"
      while IFS= read -r line; do
        printf "  %-80s\n" "${line:0:80}"
      done < "$tmp"
    else
      status_warn "Could not read sample lines."
    fi
  fi
  rm -f "$tmp"
  return $fail
}

# -----------------------------------------------------------------------------
# 3) Sqoop imported data with record counts
# -----------------------------------------------------------------------------
verify_sqoop_data() {
  section "3) Sqoop imported data (record counts and samples)"
  local fail=0

  _verify_one_table "customers" "$CUSTOMERS_DIR" "|" || ((fail++)) || true
  _verify_one_table "orders" "$ORDERS_DIR" "," || ((fail++)) || true
  return $fail
}

_verify_one_table() {
  local label="$1"
  local hdfs_path="$2"
  local sep="$3"
  shift 3
  subsection "$label: $hdfs_path"
  if ! hdfs_dir_exists "$hdfs_path"; then
    status_fail "Directory missing: $hdfs_path"
    return 1
  fi
  local tmp
  tmp=$(mktemp)
  if ! hdfs_cmd -getmerge "$hdfs_path" "$tmp" 2>/dev/null; then
    status_fail "Could not read $hdfs_path"
    rm -f "$tmp"
    return 1
  fi
  local count
  count=$(wc -l < "$tmp")
  if [[ "$count" -eq 0 ]]; then
    status_warn "Zero records."
  else
    status_ok "Record count: $count"
  fi
  printf "\n  %s sample rows (first %s lines):\n" "$label" "$SAMPLE_LINES"
  if [[ "$sep" == "|" ]]; then
    printf "  %-6s %-10s %-10s %-28s %-12s %-8s\n" "id" "first_name" "last_name" "email" "country" "status"
    printf "  %-6s %-10s %-10s %-28s %-12s %-8s\n" "------" "----------" "----------" "----------------------------" "------------" "--------"
    head -n "$SAMPLE_LINES" "$tmp" | while IFS= read -r line; do
      IFS='|' read -r id fn ln em reg co st tp <<< "$line"
      printf "  %-6s %-10s %-10s %-28s %-12s %-8s\n" "${id:-}" "${fn:0:10}" "${ln:0:10}" "${em:0:28}" "${co:0:12}" "${st:0:8}"
    done
  else
    printf "  %-8s %-8s %-12s %-22s %-10s %-8s %-10s\n" "order_id" "cust_id" "order_date" "product" "category" "amount" "status"
    printf "  %-8s %-8s %-12s %-22s %-10s %-8s %-10s\n" "--------" "--------" "------------" "----------------------" "----------" "--------" "----------"
    head -n "$SAMPLE_LINES" "$tmp" | while IFS= read -r line; do
      IFS=',' read -r oid cid odat prod cat amt st ship <<< "$line"
      printf "  %-8s %-8s %-12s %-22s %-10s %-8s %-10s\n" "${oid:-}" "${cid:-}" "${odat:0:12}" "${prod:0:22}" "${cat:0:10}" "${amt:0:8}" "${st:0:10}"
    done
  fi
  rm -f "$tmp"
  return 0
}

# -----------------------------------------------------------------------------
# 4) MapReduce results
# -----------------------------------------------------------------------------
verify_mapreduce_results() {
  section "4) MapReduce results"
  local fail=0
  local tmp
  tmp=$(mktemp)

  subsection "Output path: $OUTPUT_DIR"
  if ! hdfs_dir_exists "$OUTPUT_DIR"; then
    status_fail "MapReduce output directory missing (run run_job.sh first)."
    return 1
  fi
  if ! hdfs_cmd -getmerge "$OUTPUT_DIR" "$tmp" 2>/dev/null; then
    status_fail "Could not read output."
    return 1
  fi
  local count
  count=$(wc -l < "$tmp")
  status_ok "Result rows: $count"
  subsection "Action counts (sorted by count descending)"
  printf "  %-20s %s\n" "ACTION" "TOTAL_COUNT"
  printf "  %-20s %s\n" "--------------------" "----------"
  while IFS= read -r line; do
    IFS=$'\t' read -r action total <<< "$line"
    printf "  %-20s %s\n" "$action" "$total"
  done < "$tmp"
  rm -f "$tmp"
  return 0
}

# -----------------------------------------------------------------------------
# 5) Service health (HDFS, YARN, MySQL)
# -----------------------------------------------------------------------------
verify_services() {
  section "5) Service health"
  local fail=0

  subsection "HDFS (NameNode)"
  if hdfs_cmd -ls / &>/dev/null; then
    status_ok "HDFS is reachable (ls / succeeded)."
  else
    status_fail "HDFS not reachable."
    ((fail++)) || true
  fi

  subsection "YARN (ResourceManager)"
  if command -v curl &>/dev/null; then
    if curl -sf --connect-timeout 5 "${RM_URL}/ws/v1/cluster/info" &>/dev/null; then
      status_ok "YARN ResourceManager reachable at $RM_URL"
    else
      status_fail "YARN ResourceManager not reachable at $RM_URL"
      ((fail++)) || true
    fi
  else
    status_warn "curl not available; skipping YARN check."
  fi

  subsection "MySQL"
  if command -v mysql &>/dev/null; then
    if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        -e "SELECT 1 AS ok;" "$MYSQL_DATABASE" &>/dev/null; then
      status_ok "MySQL reachable ($MYSQL_HOST:$MYSQL_PORT, database: $MYSQL_DATABASE)."
      local cust_count order_count
      cust_count=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
          -N -e "SELECT COUNT(*) FROM customers;" "$MYSQL_DATABASE" 2>/dev/null || echo "0")
      order_count=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
          -N -e "SELECT COUNT(*) FROM orders;" "$MYSQL_DATABASE" 2>/dev/null || echo "0")
      printf "  %-20s %s\n" "customers" "$cust_count"
      printf "  %-20s %s\n" "orders" "$order_count"
    else
      status_fail "MySQL connection failed."
      ((fail++)) || true
    fi
  else
    status_warn "mysql client not found; skipping MySQL check."
  fi
  return $fail
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $SCRIPT_NAME — Data & service verification${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  local total_fail=0
  verify_hdfs_structure    || ((total_fail++)) || true
  verify_flume_logs       || ((total_fail++)) || true
  verify_sqoop_data        || ((total_fail++)) || true
  verify_mapreduce_results || ((total_fail++)) || true
  verify_services         || ((total_fail++)) || true
  echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  if [[ $total_fail -eq 0 ]]; then
    echo -e "${GREEN}  Summary: All checks passed.${NC}"
  else
    echo -e "${YELLOW}  Summary: Some checks had warnings or failures.${NC}"
  fi
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
  exit $total_fail
}

# Don't exit on first failure in a section; collect all
set +e
main "$@"
