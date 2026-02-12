#!/bin/bash
# =============================================================================
# cleanup_test_db.sh
# Drops all test databases and tables created by the test suite.
#
# Usage: ./tests/cleanup_test_db.sh [--user USER] [--password PASSWORD]
# =============================================================================
set -euo pipefail

CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
NODE1_HOST="${CH_NODE1_HOST:-localhost}"
NODE1_HTTP="${CH_NODE1_HTTP:-8123}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)     CH_USER="$2";     shift 2;;
        --password) CH_PASSWORD="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

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

echo "============================================"
echo "  ClickHouse Replication Test — Cleanup"
echo "============================================"

echo ""
echo "[1/2] Dropping database 'test_replication' ON CLUSTER company_cluster ..."
sql_node1 "DROP DATABASE IF EXISTS test_replication ON CLUSTER company_cluster SYNC;"
echo "  OK"

echo ""
echo "[2/2] Dropping database 'test_local' on node1 ..."
sql_node1 "DROP DATABASE IF EXISTS test_local SYNC;"
echo "  OK"

echo ""
echo "============================================"
echo "  Cleanup complete!"
echo "============================================"
