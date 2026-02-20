#!/usr/bin/env bash
# =============================================================================
# run_pipeline.sh — Execute full pipeline in order (run from host)
# =============================================================================
# Prerequisites: docker compose up -d, all services healthy, hadoop-client built.
# Paths use /project (mounted from repo root via docker-compose volume).
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== 1. Start Docker services ==="
docker compose up -d
echo "Waiting 45s for services to become healthy..."
sleep 45

echo ""
echo "=== 2. Verify containers ==="
docker compose ps -a

echo ""
echo "=== 3. Setup HDFS ==="
docker exec hadoop-client bash -c "for f in /project/*.sh /project/*.py; do [ -f \"\$f\" ] && sed -i 's/\r\$//' \"\$f\" 2>/dev/null; done; chmod +x /project/setup_hdfs.sh 2>/dev/null; /project/setup_hdfs.sh"

echo ""
echo "=== 4. Initialize MySQL ==="
docker exec -i mysql mysql -uroot -prootpassword < sample_data.sql
echo "MySQL sample data loaded."

echo ""
echo "=== 5. Start Flume agent (background) ==="
docker exec -d hadoop-client flume-ng agent -n agent -c conf -f /project/agent.conf
echo "Flume started. Waiting 150s for logs to accumulate..."
sleep 150

echo ""
echo "=== 6. Run Sqoop import ==="
docker exec hadoop-client /project/import_script.sh

echo ""
echo "=== 7. Run MapReduce job ==="
docker exec hadoop-client /project/run_job.sh

echo ""
echo "=== 8. Verify everything ==="
docker exec hadoop-client /project/verify_data.sh

echo ""
echo "=== 9. View MapReduce results ==="
docker exec hadoop-client hdfs dfs -cat /user/hadoopuser/project/output/log_analysis/part-*

echo ""
echo "=== Pipeline complete ==="
