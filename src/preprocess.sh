#!/bin/bash

# Common preprocess for tasks. This file should be sourced by each task.
# It defines SCRIPTDIR, OUTDIR and changes the current directory to
# CONTAINER_SRCDIR.

# We never push commits
git config --global user.email "user@example.com"
git config --global user.name "user.name"

SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

source $SCRIPTDIR/config/android-$ARG_ANDROID_VERSION.sh
# The default combination keeps the current name. Each axis that differs
# from the default adds a suffix. Keep the same as outdir_name() in
# src/aosp_build/versions.py (tests/py/test_versions_parity.py).
# TEST_MNT_OUT is only for tests (tests/test-build.sh).
OUTDIR=${TEST_MNT_OUT:-/mnt/out}/android-$ARG_ANDROID_VERSION-$ARCH
if [[ "$ARG_PLATFORM" != "$PLATFORM_DEFAULT" ]]; then
  OUTDIR=$OUTDIR-$ARG_PLATFORM
fi
if [[ "$ARG_FORM_FACTOR" != "$FORM_FACTOR_DEFAULT" ]]; then
  OUTDIR=$OUTDIR-$ARG_FORM_FACTOR
fi
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
