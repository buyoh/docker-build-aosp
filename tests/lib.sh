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
