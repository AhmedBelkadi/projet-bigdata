#!/usr/bin/env bash
# =============================================================================
# run_job.sh — Run Hadoop Streaming job: log analysis (mapper + reducer)
# =============================================================================
# 1) Checks mapper.py and reducer.py exist and are executable
# 2) Deletes HDFS output dir if it exists
# 3) Runs Hadoop Streaming: input=logs/*, output=output/log_analysis, 1 reducer
# 4) Displays results, 5) Saves to local file
# Colored output, error handling, execution time.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
readonly MAPPER="${MAPPER:-${SCRIPT_DIR}/mapper.py}"
readonly REDUCER="${REDUCER:-${SCRIPT_DIR}/reducer.py}"
readonly INPUT_PATH="${INPUT_PATH:-/user/hadoopuser/project/logs}"
readonly OUTPUT_PATH="${OUTPUT_PATH:-/user/hadoopuser/project/output/log_analysis}"
readonly NUM_REDUCERS="${NUM_REDUCERS:-1}"
readonly LOCAL_RESULT_FILE="${LOCAL_RESULT_FILE:-${SCRIPT_DIR}/log_analysis_result.txt}"

# -----------------------------------------------------------------------------
# Colored output
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# HDFS / Hadoop commands
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

find_streaming_jar() {
  local home="${HADOOP_HOME:-/opt/hadoop-3.2.1}"
  local jar
  # Prefer tools/lib (runtime jar); avoid *-sources.jar
  jar=$(find "$home" -path "*tools/lib*hadoop-streaming*.jar" ! -name "*sources*" 2>/dev/null | head -1)
  [[ -z "${jar}" ]] && jar=$(find "$home" -name "hadoop-streaming*.jar" ! -name "*sources*" 2>/dev/null | head -1)
  if [[ -z "${jar}" || ! -f "$jar" ]]; then
    log_err "Hadoop Streaming jar not found (HADOOP_HOME=$home)."
    exit 1
  fi
  echo "$jar"
}

# -----------------------------------------------------------------------------
# 1) Check mapper.py and reducer.py exist and are executable
# -----------------------------------------------------------------------------
check_scripts() {
  log_info "Checking mapper and reducer scripts ..."
  local missing=0
  for f in "$MAPPER" "$REDUCER"; do
    if [[ ! -f "$f" ]]; then
      log_err "Missing: $f"
      ((missing++)) || true
    elif [[ ! -x "$f" ]]; then
      log_warn "Not executable: $f (fixing with chmod +x)"
      chmod +x "$f"
    fi
  done
  if [[ $missing -gt 0 ]]; then
    log_err "Required scripts missing. Aborting."
    exit 1
  fi
  log_ok "mapper.py and reducer.py found and executable."
}

# -----------------------------------------------------------------------------
# 2) Delete HDFS output dir if exists
# -----------------------------------------------------------------------------
delete_output_dir() {
  log_info "Removing existing HDFS output (if any): $OUTPUT_PATH"
  if hdfs_cmd -test -d "$OUTPUT_PATH" 2>/dev/null; then
    hdfs_cmd -rm -r -f "$OUTPUT_PATH" || { log_err "Failed to delete $OUTPUT_PATH"; exit 1; }
    log_ok "Deleted $OUTPUT_PATH"
  else
    log_ok "No existing output dir to delete."
  fi
}

# -----------------------------------------------------------------------------
# 3) Run Hadoop Streaming job
# -----------------------------------------------------------------------------
run_streaming_job() {
  local jar
  jar=$(find_streaming_jar)
  log_info "Running Hadoop Streaming job ..."
  log_info "  input:  $INPUT_PATH"
  log_info "  output: $OUTPUT_PATH"
  log_info "  reducers: $NUM_REDUCERS"
  # -file ships mapper.py and reducer.py (use relative paths to avoid "outside of /" error)
  # Ensure job uses cluster HDFS (BDE sets fs.defaultFS in /etc/hadoop)
  export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-/etc/hadoop}"
  local work_dir
  work_dir=$(dirname "$MAPPER")
  export HADOOP_CLASSPATH="${jar}:${HADOOP_CLASSPATH:-}"
  ( cd "$work_dir" && hadoop org.apache.hadoop.streaming.HadoopStreaming \
    -input "$INPUT_PATH" \
    -output "$OUTPUT_PATH" \
    -mapper "python3 $(basename "$MAPPER")" \
    -reducer "python3 $(basename "$REDUCER")" \
    -file "$(basename "$MAPPER")" \
    -file "$(basename "$REDUCER")" \
    -numReduceTasks "$NUM_REDUCERS" ) \
    || { log_err "Hadoop Streaming job failed."; exit 1; }
  log_ok "Streaming job completed."
}

# -----------------------------------------------------------------------------
# 4) Fetch results (getmerge to local file), 5) Display and confirm save
# -----------------------------------------------------------------------------
fetch_display_and_save() {
  log_info "Fetching results from $OUTPUT_PATH to $LOCAL_RESULT_FILE"
  if ! hdfs_cmd -getmerge "$OUTPUT_PATH" "$LOCAL_RESULT_FILE" 2>/dev/null; then
    log_err "Failed to fetch results (no part files or HDFS error)."
    return 1
  fi
  log_ok "Results saved to $LOCAL_RESULT_FILE ($(wc -l < "$LOCAL_RESULT_FILE") lines)."
  log_info "Contents:"
  echo -e "${BOLD}--- action\ttotal_count ---${NC}"
  cat "$LOCAL_RESULT_FILE"
  return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo -e "${BOLD}=== $SCRIPT_NAME ===${NC}"
  local start_time end_time
  start_time=$(date +%s)

  check_scripts
  delete_output_dir
  run_streaming_job
  fetch_display_and_save

  end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  echo -e "${GREEN}=== $SCRIPT_NAME finished in ${elapsed}s ===${NC}"
  exit 0
}

trap 'log_err "Script failed. Exit code: $?"; exit 1' ERR
main "$@"
