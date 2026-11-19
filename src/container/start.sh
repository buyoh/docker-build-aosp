#!/bin/bash

set -eu
SCRIPTDIR=$(cd $(dirname $0) && pwd)

# usage: start.sh --resolved-config <build-config.json> <task>...
L_BUILD_CONFIG=
if [[ "${1:-}" == --resolved-config ]] && [[ $# -ge 2 ]]; then
  L_BUILD_CONFIG=$2
  shift 2
fi
if [[ -z "$L_BUILD_CONFIG" ]] || [[ $# -eq 0 ]]; then
  echo "error: usage: start.sh --resolved-config <build-config.json> <task>..." \
       "Run the tasks by build-aosp.sh." >&2
  exit 2
fi
# Read the resolved config once, not at each task: the file may be replaced
# or removed while the tasks run. preprocess.sh evaluates L_CONFIG_ENV (not
# exported). Assign first: set -e does not check the status of eval "$(...)".
L_CONFIG_ENV=$(python3 -I $SCRIPTDIR/config_env.py "$L_BUILD_CONFIG")

for task in $@; do
  case "$task" in
    build|patch|fetch|patch-revert)
      :  # ok
      ;;
    bash)  # 移行のタスクを実行しない
      exec bash $SCRIPTDIR/bash.sh "$L_BUILD_CONFIG"
      exit
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
