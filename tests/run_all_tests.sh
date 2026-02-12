#!/bin/bash
# =============================================================================
# run_all_tests.sh
# Full cycle: setup -> test -> cleanup
#
# Usage: ./tests/run_all_tests.sh [--user USER] [--password PASSWORD] [--no-cleanup]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NO_CLEANUP=false
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cleanup) NO_CLEANUP=true; shift;;
        *)            ARGS+=("$1");    shift;;
    esac
done

echo "=========================================="
echo "  Full Replication Test Suite"
echo "=========================================="

echo ""
echo ">>> Phase 1: Setup"
echo "------------------------------------------"
bash "$SCRIPT_DIR/setup_test_db.sh" "${ARGS[@]}"

echo ""
echo ">>> Phase 2: Tests"
echo "------------------------------------------"
TEST_EXIT=0
bash "$SCRIPT_DIR/test_replication.sh" "${ARGS[@]}" || TEST_EXIT=$?

if [[ "$NO_CLEANUP" == "false" ]]; then
    echo ""
    echo ">>> Phase 3: Cleanup"
    echo "------------------------------------------"
    bash "$SCRIPT_DIR/cleanup_test_db.sh" "${ARGS[@]}"
else
    echo ""
    echo ">>> Skipping cleanup (--no-cleanup)"
fi

echo ""
if [[ $TEST_EXIT -eq 0 ]]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED (exit code: $TEST_EXIT)"
fi

exit $TEST_EXIT
