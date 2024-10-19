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
mkdir -p /mnt/gen/out.$ARCH
rm out ||:
ln -s /mnt/gen/out.$ARCH/ out

# ==============================================================================
# Fetch
yes | repo init -u https://android.googlesource.com/platform/manifest \
                -b $BRANCH_AOSP_PLATFORM --depth=1

if [[ ! -d .repo/local_manifests ]]; then
  git clone https://github.com/android-rpi/local_manifests \
            .repo/local_manifests -b $BRANCH_ANDROID_RPI
fi
git -C .repo/local_manifests checkout $BRANCH_ANDROID_RPI -f

# TODO: Required??
find -name 'shallow.lock' | xargs rm ||:

repo sync -j4 --force-sync -f --verbose

# ==============================================================================
# Android kernel

if [[ $ANDROID_VERSION -eq 12 ]]; then
  cd /mnt/kernel_work
  # TO fail `isatty`, use `echo |`. It suppresses `Testing colorized output`.
  echo | repo init -u https://github.com/android-rpi/kernel_manifest -b arpi-5.10
  repo sync -j4 --force-sync -f --verbose
  cd -
fi
