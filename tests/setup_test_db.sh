#!/bin/bash
# =============================================================================
# setup_test_db.sh
# Creates test databases and tables on the ClickHouse cluster and on a single node.
#
# Usage: ./tests/setup_test_db.sh [--user USER] [--password PASSWORD]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Default connection settings ---
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
NODE1_HOST="${CH_NODE1_HOST:-localhost}"
NODE1_HTTP="${CH_NODE1_HTTP:-8123}"
NODE2_HOST="${CH_NODE2_HOST:-localhost}"
NODE2_HTTP="${CH_NODE2_HTTP:-8124}"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)     CH_USER="$2";     shift 2;;
        --password) CH_PASSWORD="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

# --- Helper: execute SQL on a specific node ---
run_sql() {
    local host="$1" port="$2" sql="$3"
    local auth_args=()
    [[ -n "$CH_USER" ]]     && auth_args+=(--user "$CH_USER")
    [[ -n "$CH_PASSWORD" ]] && auth_args+=(--password "$CH_PASSWORD")

    curl -sS "http://${host}:${port}/" \
        "${auth_args[@]}" \
        --data-binary "$sql"
}

sql_node1() { run_sql "$NODE1_HOST" "$NODE1_HTTP" "$1"; }
sql_node2() { run_sql "$NODE2_HOST" "$NODE2_HTTP" "$1"; }

echo "============================================"
echo "  ClickHouse Replication Test — Setup"
echo "============================================"

# =============================================================================
# 1. Create test database ON CLUSTER (replicated across all nodes)
# =============================================================================
echo ""
echo "[1/5] Creating database 'test_replication' ON CLUSTER company_cluster ..."
sql_node1 "CREATE DATABASE IF NOT EXISTS test_replication ON CLUSTER company_cluster;"
echo "  OK"

# =============================================================================
# 2. Create ReplicatedMergeTree table ON CLUSTER
#    Uses macros {shard} and {replica} for automatic per-node paths in ZooKeeper.
# =============================================================================
echo ""
echo "[2/5] Creating ReplicatedMergeTree table 'test_replication.events' ON CLUSTER ..."
sql_node1 "
CREATE TABLE IF NOT EXISTS test_replication.events ON CLUSTER company_cluster
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_replication/events', '{replica}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time, id);
"
echo "  OK"

# =============================================================================
# 3. Create Distributed table on top of the replicated table
#    This allows querying/inserting through any node with cluster-wide visibility.
# =============================================================================
echo ""
echo "[3/5] Creating Distributed table 'test_replication.events_distributed' ON CLUSTER ..."
sql_node1 "
CREATE TABLE IF NOT EXISTS test_replication.events_distributed ON CLUSTER company_cluster
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = Distributed('company_cluster', 'test_replication', 'events', rand());
"
echo "  OK"

# =============================================================================
# 4. Create a LOCAL-ONLY database and table (no replication, node1 only)
#    This is for comparison: data inserted here should NOT appear on other nodes.
# =============================================================================
echo ""
echo "[4/5] Creating local database 'test_local' on node1 only ..."
sql_node1 "CREATE DATABASE IF NOT EXISTS test_local;"
echo "  OK"

echo ""
echo "[5/5] Creating local MergeTree table 'test_local.events_local' on node1 only ..."
sql_node1 "
CREATE TABLE IF NOT EXISTS test_local.events_local
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time, id);
"
echo "  OK"

echo ""
echo "============================================"
echo "  Setup complete!"
echo "  - Replicated table : test_replication.events (ON CLUSTER)"
echo "  - Distributed table: test_replication.events_distributed (ON CLUSTER)"
echo "  - Local table      : test_local.events_local (node1 only)"
echo "============================================"
