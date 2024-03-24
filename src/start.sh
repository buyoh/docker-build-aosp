#!/bin/bash

set -eu
SCRIPTDIR=$(cd $(dirname $0) && pwd)

for task in $@; do
  case "$task" in
    build|patch|fetch|patch-revert)
      :  # ok
      ;;
    *)
      echo "Unknow task: $task"
      ;;
  esac
  if [[ ! -f $SCRIPTDIR/$task.sh ]]; then
    echo "error: $task.sh not found"
    exit 1
  fi
done

set -x

for task in $@; do
  echo "Running $task.sh"
  . $SCRIPTDIR/$task.sh
  echo "Done $task.sh"
done
