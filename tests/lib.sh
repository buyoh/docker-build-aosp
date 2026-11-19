#!/bin/bash

# Helpers for tests. Source this file.

REPODIR=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)
L_FAILURES=0

assert() {
  local L_DESC=$1
  shift
  if "$@"; then
    echo "ok: $L_DESC"
  else
    echo "NG: $L_DESC"
    L_FAILURES=$((L_FAILURES + 1))
  fi
}

finish() {
  [[ $L_FAILURES -eq 0 ]]
}

# usage: make_config <json> <container srcdir> <build-aosp.sh option>...
# Write the resolved config of build-aosp.sh (--print-config, docker is not
# run) for the tasks in the container. container_srcdir is replaced.
make_config() {
  local L_JSON=$1 L_SRCDIR=$2 L_DIR L_RC=0
  shift 2
  L_DIR=$(mktemp -d)
  $REPODIR/build-aosp.sh --workdir $L_DIR --outdir $L_DIR --print-config \
    "$@" > $L_DIR/config.json || L_RC=$?
  if [[ $L_RC -eq 0 ]]; then
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["container_srcdir"] = sys.argv[2]
json.dump(d, open(sys.argv[3], "w"), indent=2)
' $L_DIR/config.json "$L_SRCDIR" "$L_JSON" || L_RC=$?
  fi
  rm -rf $L_DIR
  return $L_RC
}
