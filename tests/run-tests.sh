#!/bin/bash

# Run all tests. These tests do not need docker nor AOSP sources.
# Set AOSP_WORK=<aosp work directory> to run tests against the real tree.

set -u

TESTDIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
FAILED=0

for L_TEST in $TESTDIR/test-*.sh; do
  echo "=== $(basename $L_TEST)"
  if bash $L_TEST; then
    echo "--- PASS"
  else
    echo "--- FAIL"
    FAILED=1
  fi
done

exit $FAILED
