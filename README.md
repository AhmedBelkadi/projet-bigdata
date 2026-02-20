# 📊 Big Data Mini-Project

A production-ready **Hadoop Big Data pipeline** demonstrating end-to-end data ingestion, ETL, and analytics. Ingest application logs with **Apache Flume**, import relational data with **Apache Sqoop**, and run **MapReduce** (Hadoop Streaming) for log analysis—all orchestrated with **Docker Compose** and BDE2020 Hadoop images.

**Supported OS:** Windows (PowerShell / Git Bash), macOS, Linux. All commands run via Docker; no local Java or Hadoop installation required.

---

## 1. 📋 PROJECT OVERVIEW

### Brief Description

This project implements a complete big data workflow:

- **Ingest** application logs from a Python generator into HDFS via Flume  
- **Import** e-commerce data (customers, orders) from MySQL into HDFS via Sqoop  
- **Process** log data with a MapReduce Streaming job (Python mapper/reducer) to aggregate action counts  
- **Store** all data in HDFS with a clear directory layout

All services run in Docker; no local Java or Hadoop installation is required.

### Technologies Used

| Category        | Technology              | Version / Notes                    |
|----------------|-------------------------|------------------------------------|
| **Storage**    | Apache HDFS             | 3.2.1 (BDE2020)                    |
| **Resource**   | Apache YARN             | 3.2.1 (BDE2020)                    |
| **Ingestion**  | Apache Flume            | 1.11.0                             |
| **ETL**        | Apache Sqoop            | 1.4.7 (Hadoop 2.6 binary)          |
| **Processing** | Hadoop MapReduce (Streaming) | Python 3 mapper/reducer     |
| **Database**   | MySQL                   | 8.0                                |
| **Orchestration** | Docker Compose       | v2.x                               |
| **Runtime**    | Python                  | 3.x (log generator, mapper, reducer) |

### Architecture Diagram

```
                    ┌─────────────────────────────────────────────────────────────────┐
                    │                     Docker Network: bigdata-network               │
                    │                                                                   │
  ┌──────────────┐  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
  │ log_generator│  │  │   Flume      │  │   HDFS       │  │  MapReduce (Streaming)│   │
  │ (Python)     │──┼─▶│   Agent      │─▶│   NameNode   │  │  mapper.py /         │   │
  └──────────────┘  │  │   (exec→     │  │   DataNode   │  │  reducer.py          │   │
                    │  │   HDFS sink) │  └──────┬───────┘  └──────────┬───────────┘   │
                    │  └──────────────┘         │                      │               │
                    │         ▲                  │  /user/hadoopuser/   │               │
                    │         │                  │  project/            │               │
  ┌──────────────┐  │  ┌──────┴───────┐         │  ├── logs/           │               │
  │   MySQL      │  │  │ hadoop-client│         │  ├── db_data/        │               │
  │ ecommerce_db │──┼─▶│   (Sqoop,   │────────▶│  ├── input/          │◀──────────────┘
  │ customers,   │  │  │   Flume,    │  Sqoop  │  └── output/         │
  │ orders       │  │  │   scripts)  │  import │                      │
  └──────────────┘  │  └─────────────┘         └──────────────────────┘   │
                    │         │                                            │
                    │  ┌──────┴───────┐  ┌──────────────┐                  │
                    │  │ ResourceManager│  │ NodeManager  │  (YARN)         │
                    │  │ HistoryServer  │  │              │                  │
                    │  └───────────────┘  └──────────────┘                  │
                    └─────────────────────────────────────────────────────────────────┘
```

**Data flow:** Logs → Flume → HDFS `logs/` | MySQL → Sqoop → HDFS `db_data/` | HDFS `logs/` → MapReduce → HDFS `output/log_analysis/`

---

## 2. ⚙️ PREREQUISITES

### Docker & Docker Compose

- **Docker Engine** 20.10+ (or Docker Desktop on Windows/macOS)  
- **Docker Compose** v2.x (or `docker-compose` v1.29+)  
- **Git** (optional, for cloning the repository)

No local Java, Hadoop, or Python installation required—everything runs inside containers.

### System Requirements

| Resource    | Minimum | Recommended |
|------------|---------|-------------|
| **RAM**    | 4 GB    | 8 GB        |
| **Disk**   | 10 GB free | 20 GB+   |
| **CPU**    | 2 cores | 4 cores     |

### Required Ports

Ensure the following ports are available on the host:

| Port  | Service           | Purpose                    |
|-------|-------------------|----------------------------|
| **9870** | NameNode        | HDFS Web UI                |
| **9000** | NameNode        | HDFS RPC (client/DataNode) |
| **8088** | ResourceManager | YARN Web UI                |
| **3306** | MySQL           | Database (optional expose) |

---

## 3. 📁 PROJECT STRUCTURE

### Directory Tree

```
bigdata-mini-project/
├── docker-compose.yml          # Stack: NameNode, DataNode, RM, NM, HistoryServer, MySQL, hadoop-client
├── hadoop.env                  # Hadoop cluster config (HDFS, YARN, MapReduce) for BDE2020
├── .env.example                # Example env vars (MySQL); copy to .env
├── .env                        # Local overrides (not committed)
├── .gitattributes              # LF line endings for .sh, .py, .conf
│
├── Dockerfile.hadoop           # Optional: custom base with Python 3.8, Flume, Sqoop
├── Dockerfile.hadoop-client    # Client image: NodeManager base + Flume, Sqoop, Python, MySQL connector
│
├── conf/                       # Client-side Hadoop config (baked into hadoop-client image)
│   ├── core-site-client.xml    # fs.defaultFS → hdfs://namenode:9000
│   ├── mapred-site-client.xml  # mapreduce.framework.name=local; YARN container env
│   └── yarn-site-client.xml    # ResourceManager address for Sqoop (YARN submits)
│
├── setup_hdfs.sh               # Create HDFS dirs: logs, db_data, input, output; chmod 755
├── sample_data.sql             # MySQL: ecommerce_db, customers (500), orders (2000)
├── agent.conf                  # Flume: exec source → memory channel → HDFS sink
├── log_generator.py            # Python: realistic JSON logs to stdout; --rate, --duration
│
├── import_script.sh            # Sqoop: customers (ACTIVE) + orders (2024+, DELIVERED) → HDFS
├── mapper.py                   # MapReduce mapper: log line → action\t1
├── reducer.py                  # MapReduce reducer: aggregate counts, sort by count desc
├── run_job.sh                  # Hadoop Streaming: logs → mapper/reducer → output/log_analysis
├── verify_data.sh              # Verification: HDFS, Flume, Sqoop, MapReduce, service health
├── run_pipeline.sh             # One-command: setup → MySQL → Flume → Sqoop → MR → verify (bash)
│
├── sample_log.txt              # Sample log file for testing MapReduce without Flume
├── rapport-bigdata.tex         # LaTeX report template (French)
├── figures/                    # Screenshots for the report (to be created during runs)
│   └── (architecture.png, flume-running.png, hdfs-logs-listing.png, etc.)
└── README.md                   # This file
```

### Key Files Description

| File | Purpose |
|------|---------|
| **docker-compose.yml** | Defines 7 services; mounts project as `/project` in hadoop-client. |
| **hadoop.env** | BDE2020-style env vars (CORE_CONF_*, HDFS_CONF_*, YARN_CONF_*, MAPRED_CONF_*). |
| **setup_hdfs.sh** | Idempotent; creates `/user/hadoopuser/project/{logs,db_data,input,output}` and sets permissions. |
| **agent.conf** | Flume agent: exec source runs `log_generator.py`, memory channel, HDFS sink to `logs/`. |
| **import_script.sh** | Sqoop imports with `-D mapreduce.framework.name=yarn`; writes to `db_data/customers` and `db_data/orders`. |
| **run_job.sh** | Runs Hadoop Streaming with mapper.py/reducer.py; input=logs, output=output/log_analysis. |
| **verify_data.sh** | Checks HDFS layout, log files, Sqoop part files, MapReduce output, and service health. |

---

## 4. 🚀 QUICK START GUIDE

### Get the Project

**Option A – Git clone:**
```bash
git clone https://github.com/AhmedBelkadi/bigdata-mini-project.git
cd bigdata-mini-project
```
(Replace `AhmedBelkadi` with the repo owner’s GitHub username.)

**Option B – Download ZIP:**  
From GitHub: Code → Download ZIP, then extract and `cd` into the project folder.

### Start Services

```bash
# Optional: set MySQL credentials
cp .env.example .env
# Edit .env if needed (MYSQL_ROOT_PASSWORD, MYSQL_USER, MYSQL_PASSWORD)

# Build the Hadoop client image (first time only)
docker compose build hadoop-client

# Start all services in detached mode
docker compose up -d
```

### Wait for Services (30–60 seconds)

```bash
docker compose ps
```

Wait until all containers show **healthy** (or **Up**). NameNode and DataNode may take 1–2 minutes to become healthy.

### Setup HDFS

From the **host** (recommended):

```bash
docker exec hadoop-client /project/setup_hdfs.sh
```

From **inside** the hadoop-client container:

```bash
docker exec -it hadoop-client bash
cd /project
./setup_hdfs.sh
exit
```

If you use a `scripts/` directory (e.g. symlink or copy), you can run `./scripts/setup_hdfs.sh` from `/project`.

### Step-by-Step First Run

Run these from the **project root** (same folder as `docker-compose.yml`).

1. **Start stack:** `docker compose up -d`  
2. **Wait:** 45–60 seconds; run `docker compose ps` until all containers are healthy.  
3. **Setup HDFS:** `docker exec hadoop-client /project/setup_hdfs.sh`  
4. **Load MySQL:**
   - **Linux / macOS / Git Bash:**  
     `docker exec -i mysql mysql -uroot -prootpassword < sample_data.sql`
   - **Windows PowerShell:**  
     `Get-Content sample_data.sql -Raw | docker exec -i mysql mysql -uroot -prootpassword`  
5. **Start Flume:** `docker exec -d hadoop-client flume-ng agent -n agent -c conf -f /project/agent.conf`  
6. **Wait 2–3 minutes** for logs to accumulate in HDFS.  
7. **Sqoop import:** `docker exec hadoop-client /project/import_script.sh`  
8. **MapReduce job:** `docker exec hadoop-client /project/run_job.sh`  
9. **Verify:** `docker exec hadoop-client /project/verify_data.sh`  
10. **View results:** `docker exec hadoop-client hdfs dfs -cat /user/hadoopuser/project/output/log_analysis/*`

### One-Command Pipeline (Linux, macOS, Git Bash)

If you use **bash** (Linux, macOS, or Git Bash on Windows):

```bash
./run_pipeline.sh
```

This script starts services, waits, sets up HDFS, loads MySQL, starts Flume, waits ~2.5 min, runs Sqoop, runs MapReduce, and verifies. **On Windows PowerShell**, run the steps manually (or use Git Bash for `./run_pipeline.sh`).

---

## 5. 🔧 DETAILED SETUP

### Environment Configuration

Copy the example env file and adjust if needed:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `MYSQL_ROOT_PASSWORD` | `rootpassword` | MySQL root password |
| `MYSQL_USER` | `ecommerce` | MySQL app user |
| `MYSQL_PASSWORD` | `ecommercepass` | MySQL app password |

The hadoop-client container receives `MYSQL_HOST=mysql`, `MYSQL_PORT=3306`, and `MYSQL_DATABASE=ecommerce_db` from docker-compose.

### MySQL Initialization

Load the sample database and tables (idempotent; drops and recreates tables):

```bash
# From host (use full path to sample_data.sql on your machine)
docker exec -i mysql mysql -uroot -prootpassword ecommerce_db < sample_data.sql
```

- **Database:** `ecommerce_db`  
- **Tables:** `customers` (500 rows), `orders` (2000 rows)  
- **Note:** `sample_data.sql` sets `cte_max_recursion_depth = 10000` for recursive CTEs (MySQL 8.0).

### HDFS Setup

The script `setup_hdfs.sh`:

- Waits for HDFS to be ready (configurable attempts).  
- Creates `/user/hadoopuser/project` and subdirs: `logs`, `db_data`, `input`, `output`.  
- Sets permissions to 755.  
- Verifies and lists the structure.

Run it after the stack is up:

```bash
docker exec hadoop-client /project/setup_hdfs.sh
```

On Windows, ensure scripts use LF line endings (e.g. via `.gitattributes` or run `sed -i 's/\r$//' /project/setup_hdfs.sh` inside the container once).

### Service Verification

- **Containers:** `docker compose ps` — all should be Up (and healthy where healthchecks exist).  
- **HDFS:** Open http://localhost:9870 and browse `/user/hadoopuser/project`.  
- **YARN:** Open http://localhost:8088 for applications and cluster info.  
- **MySQL:** `docker exec mysql mysqladmin ping -uroot -prootpassword` (or connect on port 3306).

---

## 6. 🔄 RUNNING THE PIPELINE

Run these from the host with `docker exec hadoop-client` or from inside the container (`docker exec -it hadoop-client bash`, then `cd /project`).

### Step 1: Start Flume Ingestion

Flume runs `log_generator.py` and writes events to HDFS `logs/`.

**Background (recommended):**

```bash
docker exec -d hadoop-client flume-ng agent -n agent -c conf -f /project/agent.conf
```

**Foreground (for debugging):**

```bash
docker exec -it hadoop-client flume-ng agent -n agent -c conf -f /project/agent.conf
# Stop with Ctrl+C
```

Allow **2–3 minutes** for log files to appear under `/user/hadoopuser/project/logs/`.

### Step 2: Import Data with Sqoop

Imports **customers** (status='ACTIVE', 3 mappers, pipe delimiter) and **orders** (order_date ≥ 2024-01-01, status='DELIVERED', 2 mappers, comma delimiter).

```bash
docker exec hadoop-client /project/import_script.sh
```

Output:

- `/user/hadoopuser/project/db_data/customers/` (part-m-*)
- `/user/hadoopuser/project/db_data/orders/` (part-m-*)

### Step 3: Run MapReduce Job

Runs a Hadoop Streaming job: input = `logs/`, output = `output/log_analysis/`, 1 reducer.

```bash
docker exec hadoop-client /project/run_job.sh
```

The script checks for mapper/reducer, removes existing output, runs the job, then fetches and displays results (and saves to `log_analysis_result.txt`).

### Step 4: View Results

**From HDFS:**

```bash
docker exec hadoop-client hdfs dfs -cat /user/hadoopuser/project/output/log_analysis/*
```

**Local copy (after run_job.sh):**  
`/project/log_analysis_result.txt` inside the container (or project root on host if mounted).

---

## 7. 📊 MONITORING & VERIFICATION

### Access Hadoop Web UIs

| Service | URL | Description |
|---------|-----|-------------|
| **HDFS NameNode** | http://localhost:9870 | Browse namespace, cluster summary, datanodes |
| **YARN ResourceManager** | http://localhost:8088 | Applications, nodes, scheduler |
| **History Server** | (internal) http://historyserver:8188 | Application history and logs (linked from YARN UI) |

### View Logs

- **Container logs:** `docker compose logs -f <service_name>` (e.g. `namenode`, `hadoop-client`).  
- **Flume:** If run in foreground, logs go to the terminal; otherwise check container logs.  
- **Sqoop / MapReduce:** Output is printed to the terminal when run via the scripts.

### Verify Data

Run the verification script:

```bash
docker exec hadoop-client /project/verify_data.sh
```

It reports:

- HDFS directory structure and file counts  
- Flume log files and sample lines  
- Sqoop data (customers, orders) with record counts and samples  
- MapReduce output and sample lines  
- Service health (optional checks)

### Common Issues & Quick Checks

- **No files in logs/:** Ensure Flume ran long enough (2–3 min); check agent.conf and path to `log_generator.py`.  
- **Sqoop fails:** Ensure MySQL is up and `sample_data.sql` has been loaded.  
- **MapReduce “input path does not exist”:** Ensure HDFS setup ran and `logs/` contains at least one file (or put a sample file for testing).  
- **Script “command not found” or syntax errors:** Fix CRLF line endings (see §10 Troubleshooting). On Windows: use Git Bash for shell scripts, or fix with `sed -i 's/\r$//' /project/*.sh` inside the container. For MySQL load: use PowerShell `Get-Content sample_data.sql -Raw | docker exec -i mysql mysql -uroot -prootpassword`.

---

## 8. 🧩 PROJECT COMPONENTS

### Component Overview

| Component | Role |
|-----------|------|
| **NameNode** | HDFS metadata and namespace; RPC 9000, Web UI 9870 |
| **DataNode** | Stores HDFS blocks; registers with NameNode |
| **ResourceManager** | YARN resource allocation and job scheduling; UI 8088 |
| **NodeManager** | Runs YARN containers and tasks |
| **History Server** | YARN application history and log aggregation (8188) |
| **MySQL** | Relational source for Sqoop (ecommerce_db) |
| **hadoop-client** | Custom image: Hadoop CLI, Flume, Sqoop, Python; runs all scripts |

### Configuration Files

| File | Purpose |
|------|---------|
| **hadoop.env** | Cluster-wide HDFS, YARN, MapReduce settings for BDE2020 images. |
| **conf/core-site-client.xml** | Client: `fs.defaultFS=hdfs://namenode:9000`. |
| **conf/mapred-site-client.xml** | Client: default `mapreduce.framework.name=local`; YARN container env (HADOOP_MAPRED_HOME) for Sqoop. |
| **conf/yarn-site-client.xml** | Client: ResourceManager address for job submission (Sqoop uses YARN). |
| **agent.conf** | Flume: exec source (log_generator.py), memory channel, HDFS sink (roll by time/size/count). |

### Scripts Usage

| Script | Usage | Notes |
|--------|--------|------|
| **setup_hdfs.sh** | `docker exec hadoop-client /project/setup_hdfs.sh` | Idempotent; run after stack is up. |
| **import_script.sh** | `docker exec hadoop-client /project/import_script.sh` | Requires MySQL up and sample data loaded. |
| **run_job.sh** | `docker exec hadoop-client /project/run_job.sh` | Requires at least one file in HDFS `logs/`. |
| **verify_data.sh** | `docker exec hadoop-client /project/verify_data.sh` | No prerequisites; reports status of all steps. |
| **run_pipeline.sh** | `./run_pipeline.sh` (from host) | Full pipeline: setup → MySQL → Flume (wait) → Sqoop → MR → verify. |

---

## 9. 📈 RESULTS & ANALYSIS

### Sample Output

**MapReduce log analysis** (action counts, sorted by count descending):

```
action    total_count
click     1
view      1
```

With more Flume data, you would see higher counts (e.g. `view 1245`, `login 892`).

**Sqoop imports:**

- **Customers:** 400 rows (ACTIVE), 3 part files, pipe-separated.  
- **Orders:** 1100 rows (2024+, DELIVERED), 2 part files, comma-separated.

**Flume:** Log files under `logs/` with JSON lines (timestamp, user_id, action, page, etc.).

### Interpretation

- **mapper.py** reads each log line (JSON or pipe-separated), extracts `action`, and emits `action\t1`.  
- **reducer.py** sums counts per action and sorts by total count descending.  
- Output format: `action\ttotal_count`, suitable for dashboards or further processing.

### Performance Metrics

- **Sqoop:** Customers ~30–40 s, orders ~20–30 s (YARN); depends on cluster resources.  
- **MapReduce:** Typically 10–20 s for moderate log volume (local mode).  
- **Flume:** Throughput depends on `log_generator.py` rate and channel capacity (default 5 events/s).

---

## 10. 🔧 TROUBLESHOOTING

### Common Errors and Solutions

| Error / Symptom | Cause | Solution |
|------------------|--------|----------|
| **HDFS not ready** | NameNode/DataNode not yet healthy | Wait 1–2 min; run `setup_hdfs.sh` again. |
| **Flume: “Cannot find log_generator”** | Wrong path in agent.conf or file missing | Ensure `log_generator.py` is at `/project/log_generator.py` and path in agent.conf is correct. |
| **Sqoop: connection refused** | MySQL not reachable or not up | Check `docker compose ps`; run `sample_data.sql` if tables are missing. |
| **Sqoop: Class X not found** | Generated class not on classpath in local mode | Import script uses `-D mapreduce.framework.name=yarn`; ensure client has yarn-site and mapred env (HADOOP_MAPRED_HOME) in mapred-site. |
| **MySQL: recursive CTE aborted** | MySQL recursion limit | `sample_data.sql` sets `SET SESSION cte_max_recursion_depth = 10000`; ensure it is executed. |
| **MapReduce: input path does not exist** | No data in logs/ or wrong fs.defaultFS | Run setup_hdfs.sh; put at least one file in `logs/` (Flume or manual); client must have core-site with fs.defaultFS. |
| **MapReduce: Python SyntaxError** | f-strings / Python 3.6+ syntax on Python 3.5 | mapper.py and reducer.py are written for Python 3.5 compatibility (no f-strings). |
| **Permission denied (HDFS)** | User or permissions | Re-run `setup_hdfs.sh`; check hadoop.env (e.g. dfs.permissions.enabled=false). |
| **hadoop-client build: apt 404** | Debian Stretch EOL | Dockerfile uses archive.debian.org; ensure Dockerfile.hadoop-client has the archive sources. |
| **Script fails with \r or bad substitution** | CRLF line endings or shell escaping | Run `sed -i 's/\r$//' /project/<script>.sh` in container; use `.gitattributes` with `eol=lf` for .sh/.py. |

### Debug Commands

```bash
# Check HDFS connectivity from client
docker exec hadoop-client hdfs dfs -ls /user/hadoopuser/project

# List log files
docker exec hadoop-client hdfs dfs -ls /user/hadoopuser/project/logs

# Check MySQL from client (if mysql client installed)
docker exec hadoop-client bash -c "mysql -h mysql -uroot -prootpassword -e 'SELECT 1' ecommerce_db"

# Sqoop list-tables (connectivity test)
docker exec hadoop-client sqoop list-tables --connect 'jdbc:mysql://mysql:3306/ecommerce_db' --username root --password rootpassword

# View MapReduce job output
docker exec hadoop-client hdfs dfs -cat /user/hadoopuser/project/output/log_analysis/part-*
```

Use **verify_data.sh** for an overall health and data check.

---

## 11. 🧹 CLEANING UP

### Stop Services

```bash
docker compose down
```

Containers are removed; **named volumes** (HDFS data, MySQL data, history server) are preserved.

### Remove Volumes

To delete all persistent data (HDFS, MySQL, history server):

```bash
docker compose down -v
```

### Clean HDFS (Optional)

If you only want to reset HDFS paths but keep the stack:

```bash
docker exec hadoop-client hdfs dfs -rm -r -f /user/hadoopuser/project/logs/* \
  /user/hadoopuser/project/db_data/* /user/hadoopuser/project/output/*
# Then re-run setup_hdfs.sh if you want empty dirs again
```

### Remove Client Image

```bash
docker rmi bigdata-mini-project/hadoop-client:latest
```

Rebuild with `docker compose build hadoop-client` when needed.

---

## 12. 📚 REFERENCES

### Documentation

| Resource | Link |
|----------|------|
| **BDE2020 Docker Hadoop** | [GitHub – big-data-europe/docker-hadoop](https://github.com/big-data-europe/docker-hadoop) |
| **Apache Hadoop** | [hadoop.apache.org](https://hadoop.apache.org/docs/stable/) |
| **Hadoop Streaming** | [Hadoop Streaming Guide](https://hadoop.apache.org/docs/stable/hadoop-streaming/HadoopStreaming.html) |
| **Apache Flume** | [Flume User Guide](https://flume.apache.org/releases/content/1.11.0/FlumeUserGuide.html) |
| **Apache Sqoop** | [Sqoop Documentation](https://sqoop.apache.org/docs/1.4.7/SqoopUserGuide.html) |
| **MySQL 8.0** | [MySQL Reference Manual](https://dev.mysql.com/doc/refman/8.0/en/) |

### Web UIs (after starting the stack)

- **HDFS:** http://localhost:9870  
- **YARN:** http://localhost:8088  

---

**License:** See repository or project license file.  
**Contributing:** Follow standard Git workflow (branch, commit, pull request).
