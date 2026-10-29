#!/bin/bash

set -eux

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

# ==============================================================================
# Fetch

# Pin the version of the repo tool itself.
REPO_REV=v2.55.1

yes | repo init -u https://android.googlesource.com/platform/manifest \
                -b $BRANCH_AOSP_PLATFORM --depth=1 --repo-rev=$REPO_REV

if [[ -n $ARG_RPI ]]; then
  if [[ ! -d .repo/local_manifests ]]; then
    git clone https://github.com/android-rpi/local_manifests \
              .repo/local_manifests -b $BRANCH_ANDROID_RPI
  fi
  git -C .repo/local_manifests checkout $BRANCH_ANDROID_RPI -f
fi

# TODO: Required??
find -name 'shallow.lock' | xargs rm ||:

repo sync -j4 --force-sync -f --verbose

# ==============================================================================
# Android kernel

if [[ -n $ARG_RPI ]]; then
  if [[ $ANDROID_VERSION -ge 12 ]]; then
    cd /mnt/kernel_work
    # TO fail `isatty`, use `echo |`. It suppresses `Testing colorized output`.
    echo | repo init -u https://github.com/android-rpi/kernel_manifest \
                     -b $BRANCH_KERNEL_RPI --repo-rev=$REPO_REV
    repo sync -j4 --force-sync -f --verbose
    cd -
  fi
fi