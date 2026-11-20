#!/bin/bash

set -eux

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

# ==============================================================================
# Fetch

if [[ -z $ARG_RPI ]] && [[ -e .repo/local_manifests ]]; then
  # repo reads every xml in it. A workdir of RPi (the local manifests of
  # android-rpi) would mix the RPi projects into the non-RPi tree
  # (docs-ai/task/build-reproducibility-review/11).
  echo "error: .repo/local_manifests exists, but this is a non-RPi build." >&2
  echo "       The workdir seems to be used for RPi. Use another --workdir," >&2
  echo "       or remove .repo/local_manifests if it is not needed." >&2
  exit 1
fi

# REPO_REV (the version of the repo tool itself) is in the resolved config.
yes | repo init -u https://android.googlesource.com/platform/manifest \
                -b $BRANCH_AOSP_PLATFORM --depth=1 --repo-rev=$REPO_REV

if [[ -n $ARG_RPI ]]; then
  if [[ ! -d .repo/local_manifests ]]; then
    git clone https://github.com/android-rpi/local_manifests \
              .repo/local_manifests -b $BRANCH_ANDROID_RPI
  fi
  git -C .repo/local_manifests checkout $BRANCH_ANDROID_RPI -f
fi

# Stale locks of interrupted fetches. The repo tool makes each project's .git
# a symlink to .repo/projects, so the locks exist only under .repo.
find .repo -name 'shallow.lock' -delete ||:

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