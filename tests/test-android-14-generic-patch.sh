#!/bin/bash

# Tests for src/patches/android-14-generic.patch against the real AOSP tree
# for non-RPi (android-14.0.0_r74). This test is skipped if AOSP_WORK_GENERIC
# is not set. It does not modify the tree.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

if [[ -z "${AOSP_WORK_GENERIC:-}" ]]; then
  echo "skip: AOSP_WORK_GENERIC is not set"
  exit 0
fi

PATCHFILE=$REPODIR/src/patches/android-14-generic.patch
L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# The patch is fully applied to the tree or fully not applied, without fuzz
# and in exactly one direction (the same rule as patcher.sh).
reverse_or_forward_applies() {
  local L_FORWARD=0 L_REVERSE=0
  (cd $AOSP_WORK_GENERIC && \
    patch -p0 -f -N -F0 --dry-run < $PATCHFILE) > $L_TMP/log 2>&1 && L_FORWARD=1
  (cd $AOSP_WORK_GENERIC && \
    patch -p0 -f -N -F0 -R --dry-run < $PATCHFILE) > $L_TMP/log 2>&1 && L_REVERSE=1
  [[ $((L_FORWARD + L_REVERSE)) -eq 1 ]]
}
assert "android-14-generic.patch is consistent with $AOSP_WORK_GENERIC" \
  reverse_or_forward_applies

# The patch applies to the pristine file and adds the launcher.
patch_applies_to_head() {
  local L_F=device/google/atv/products/sdk_atv_x86.mk
  mkdir -p $L_TMP/pristine/$(dirname $L_F)
  git -C $AOSP_WORK_GENERIC/device/google/atv show \
    HEAD:${L_F#device/google/atv/} > $L_TMP/pristine/$L_F || return 1
  (cd $L_TMP/pristine && patch -p0 -f -N -F0 < $PATCHFILE) > /dev/null && \
    grep -q TvSampleLeanbackLauncher $L_TMP/pristine/$L_F
}
assert "the patch applies to HEAD of device/google/atv" patch_applies_to_head

finish
