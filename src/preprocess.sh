#!/bin/bash

# Common preprocess for tasks. This file should be sourced by each task.
# It defines SCRIPTDIR, OUTDIR and changes the current directory to
# CONTAINER_SRCDIR.

# We never push commits
git config --global user.email "user@example.com"
git config --global user.name "user.name"

SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

source $SCRIPTDIR/config/android-$ARG_ANDROID_VERSION.sh
OUTDIR=/mnt/out/android-$ARG_ANDROID_VERSION-$ARCH
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
