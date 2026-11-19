#!/bin/bash

# Common preprocess for tasks. This file should be sourced by each task.
# It defines SCRIPTDIR, OUTDIR and the variables of the resolved config, and
# changes the current directory to CONTAINER_SRCDIR.

# We never push commits
git config --global user.email "user@example.com"
git config --global user.name "user.name"

SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

# The resolved config written by build-aosp.sh (src/host/aosp_build/versions/).
# config_env.py prints the assignments of the variables (ANDROID_VERSION,
# ARCH, LUNCH_CHOICE, ...). start.sh runs it once and sets L_CONFIG_ENV.
# bash.sh sets only L_BUILD_CONFIG (the path).
# Assign first: set -e does not check the status of eval "$(...)".
if [[ -z "${L_CONFIG_ENV:-}" ]]; then
  if [[ -z "${L_BUILD_CONFIG:-}" ]]; then
    echo "error: No resolved config. Run the tasks by build-aosp.sh." >&2
    exit 2
  fi
  L_CONFIG_ENV=$(python3 -I $SCRIPTDIR/config_env.py "$L_BUILD_CONFIG")
fi
eval "$L_CONFIG_ENV"

if [[ -n "$PYTHON2_AS_PYTHON" ]]; then
  # TODO: Retest this
  ln -sf /usr/bin/python2 /usr/bin/python
fi

# TEST_MNT_OUT is only for tests (tests/test-build.sh).
OUTDIR=${TEST_MNT_OUT:-/mnt/out}/$OUTDIR_NAME
mkdir -p $OUTDIR

cd $CONTAINER_SRCDIR
if [[ "$ARG_NO_GEN" == "false" ]]; then
  if [[ -e out ]] && [[ ! -L out ]]; then
    echo "The 'out' directory already exists and is not a symlink."
    exit 1
  fi
  mkdir -p /mnt/gen/out.$ARCH
  if [[ -e out ]]; then
    rm out
  fi
  ln -s /mnt/gen/out.$ARCH/ out
fi
