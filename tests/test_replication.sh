#!/bin/bash
# =============================================================================
# test_replication.sh
# Tests replication by inserting data and verifying it appears on all nodes.
# Run setup_test_db.sh first!
#
# Usage: ./tests/test_replication.sh [--user USER] [--password PASSWORD]
# =============================================================================
set -euo pipefail

# --- Default connection settings ---
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
NODE1_HOST="${CH_NODE1_HOST:-localhost}"
NODE1_HTTP="${CH_NODE1_HTTP:-8123}"
NODE2_HOST="${CH_NODE2_HOST:-localhost}"
NODE2_HTTP="${CH_NODE2_HTTP:-8124}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)     CH_USER="$2";     shift 2;;
        --password) CH_PASSWORD="$2"; shift 2;;
        *) echo "Unknown argument: $1"; exit 1;;
    esac
done

# --- Helper ---
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

PASS=0
FAIL=0

assert_eq() {
    local test_name="$1" expected="$2" actual="$3"
    # Trim whitespace
    expected="$(echo "$expected" | xargs)"
    actual="$(echo "$actual" | xargs)"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $test_name (got: $actual)"
        ((PASS++))
    else
        echo "  FAIL: $test_name — expected [$expected], got [$actual]"
        ((FAIL++))
    fi
}

echo "============================================"
echo "  ClickHouse Replication Tests"
echo "============================================"

# =============================================================================
# TEST 1: Insert data into replicated table on node1, verify on all nodes
# =============================================================================
echo ""
echo "--- Test 1: ReplicatedMergeTree replication ---"
echo "  Inserting 5 rows into test_replication.events via node1 ..."

sql_node1 "
INSERT INTO test_replication.events (id, event_type, payload) VALUES
    (1, 'login',    'user=alice'),
    (2, 'click',    'page=home'),
    (3, 'purchase', 'item=widget'),
    (4, 'logout',   'user=alice'),
    (5, 'login',    'user=bob');
"

# Give replication a moment
echo "  Waiting 3 seconds for replication ..."
sleep 3

COUNT_N1=$(sql_node1 "SELECT count() FROM test_replication.events;")
COUNT_N2=$(sql_node2 "SELECT count() FROM test_replication.events;")

assert_eq "Node1 has 5 rows" "5" "$COUNT_N1"
assert_eq "Node2 has 5 rows (replicated)" "5" "$COUNT_N2"

# =============================================================================
# TEST 2: Insert via node2, verify on node1
# =============================================================================
echo ""
echo "--- Test 2: Insert on node2, replicate to node1 ---"
echo "  Inserting 3 rows via node2 ..."

sql_node2 "
INSERT INTO test_replication.events (id, event_type, payload) VALUES
    (6, 'signup',   'user=charlie'),
    (7, 'click',    'page=pricing'),
    (8, 'purchase', 'item=gadget');
"

echo "  Waiting 3 seconds for replication ..."
sleep 3

COUNT_N1=$(sql_node1 "SELECT count() FROM test_replication.events;")
COUNT_N2=$(sql_node2 "SELECT count() FROM test_replication.events;")

assert_eq "Node1 has 8 rows" "8" "$COUNT_N1"
assert_eq "Node2 has 8 rows" "8" "$COUNT_N2"

# =============================================================================
# TEST 3: Insert via Distributed table, verify on all nodes
# =============================================================================
echo ""
echo "--- Test 3: Insert via Distributed table ---"
echo "  Inserting 2 rows via events_distributed on node2 ..."

sql_node2 "
INSERT INTO test_replication.events_distributed (id, event_type, payload) VALUES
    (9,  'click',  'page=about'),
    (10, 'logout', 'user=bob');
"

echo "  Waiting 5 seconds for distribution + replication ..."
sleep 5

COUNT_N1=$(sql_node1 "SELECT count() FROM test_replication.events;")
COUNT_N2=$(sql_node2 "SELECT count() FROM test_replication.events;")

assert_eq "Node1 has 10 rows" "10" "$COUNT_N1"
assert_eq "Node2 has 10 rows" "10" "$COUNT_N2"

# =============================================================================
# TEST 4: Verify data consistency — same content on all replicas
# =============================================================================
echo ""
echo "--- Test 4: Data consistency across replicas ---"

HASH_N1=$(sql_node1 "SELECT groupBitXor(cityHash64(*)) FROM test_replication.events;")
HASH_N2=$(sql_node2 "SELECT groupBitXor(cityHash64(*)) FROM test_replication.events;")

assert_eq "Node1 hash == Node2 hash" "$HASH_N1" "$HASH_N2"

# =============================================================================
# TEST 5: Local-only table — data must NOT replicate
# =============================================================================
echo ""
echo "--- Test 5: Local MergeTree table (no replication) ---"
echo "  Inserting 3 rows into test_local.events_local on node1 ..."

sql_node1 "
INSERT INTO test_local.events_local (id, event_type, payload) VALUES
    (100, 'local_event', 'only_on_node1_a'),
    (101, 'local_event', 'only_on_node1_b'),
    (102, 'local_event', 'only_on_node1_c');
"

LOCAL_COUNT_N1=$(sql_node1 "SELECT count() FROM test_local.events_local;")
assert_eq "Node1 local table has 3 rows" "3" "$LOCAL_COUNT_N1"

# Node2 should NOT have this database/table at all
echo "  Checking that test_local DB does NOT exist on node2 ..."
NODE2_HAS_DB=$(sql_node2 "SELECT count() FROM system.databases WHERE name = 'test_local';" || echo "error")
assert_eq "Node2 does not have test_local DB" "0" "$NODE2_HAS_DB"

# =============================================================================
# TEST 6: Check replication queue is clean (no stuck tasks)
# =============================================================================
echo ""
echo "--- Test 6: Replication queue health ---"

QUEUE_N1=$(sql_node1 "SELECT count() FROM system.replication_queue WHERE is_currently_executing = 0 AND num_tries > 1;")
QUEUE_N2=$(sql_node2 "SELECT count() FROM system.replication_queue WHERE is_currently_executing = 0 AND num_tries > 1;")

assert_eq "Node1 has no stuck replication tasks" "0" "$QUEUE_N1"
assert_eq "Node2 has no stuck replication tasks" "0" "$QUEUE_N2"

# =============================================================================
# TEST 7: Verify system.replicas metadata
# =============================================================================
echo ""
echo "--- Test 7: system.replicas metadata ---"

for node_fn in sql_node1 sql_node2; do
    node_name="${node_fn#sql_}"
    is_leader=$($node_fn "SELECT is_leader FROM system.replicas WHERE database = 'test_replication' AND table = 'events';")
    is_readonly=$($node_fn "SELECT is_readonly FROM system.replicas WHERE database = 'test_replication' AND table = 'events';")
    total_replicas=$($node_fn "SELECT total_replicas FROM system.replicas WHERE database = 'test_replication' AND table = 'events';")
    active_replicas=$($node_fn "SELECT active_replicas FROM system.replicas WHERE database = 'test_replication' AND table = 'events';")

    echo "  $node_name: leader=$is_leader readonly=$is_readonly total=$total_replicas active=$active_replicas"
    assert_eq "$node_name is not readonly" "0" "$(echo "$is_readonly" | xargs)"
    assert_eq "$node_name sees 2 total replicas" "2" "$(echo "$total_replicas" | xargs)"
    assert_eq "$node_name sees 2 active replicas" "2" "$(echo "$active_replicas" | xargs)"
done

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "============================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
