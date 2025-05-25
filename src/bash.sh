#!/bin/bash

set -eux

# We never push commits
git config --global user.email "user@example.com"
git config --global user.name "user.name"

SCRIPTDIR=$(cd $(dirname $0) && pwd)

source $SCRIPTDIR/config/android-$ARG_ANDROID_VERSION.sh
OUTDIR=/mnt/out/android-$ARG_ANDROID_VERSION-$ARCH
mkdir -p $OUTDIR

cd /mnt/work
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

exec bash
