#!/bin/bash

# Tests for the generic patch of Android 16
# (src/common/patches/android-16-generic.patch) against the real AOSP tree for
# non-RPi (android-16.0.0_r4). This test is skipped if AOSP_WORK_GENERIC_16 is
# not set. It does not modify the tree.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

if [[ -z "${AOSP_WORK_GENERIC_16:-}" ]]; then
  echo "skip: AOSP_WORK_GENERIC_16 is not set"
  exit 0
fi

PATCHDIR=$REPODIR/src/common/patches
TOP_PATCH=android-16-generic.patch
L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# 16 has no goldfish patch: the upstream pins the 6.1 kernel of the TV
# emulator (r3 and later).
assert "no goldfish patch for 16" \
  test ! -e $PATCHDIR/device/generic/goldfish/android-16-generic.patch
assert "the upstream pins the 6.1 kernel of the TV emulator" \
  grep -qx 'TARGET_KERNEL_USE := 6.1' \
    $AOSP_WORK_GENERIC_16/device/google/atv/emulator_x86/x86_64.mk

# The patch is fully applied to the tree or fully not applied, without fuzz
# and in exactly one direction (the same rule as patcher.sh).
reverse_or_forward_applies() {
  local L_FORWARD=0 L_REVERSE=0
  (cd $AOSP_WORK_GENERIC_16 && patch -p0 -f -N -F0 --dry-run < $PATCHDIR/$TOP_PATCH) \
    > $L_TMP/log 2>&1 && L_FORWARD=1
  (cd $AOSP_WORK_GENERIC_16 && patch -p0 -f -N -F0 -R --dry-run < $PATCHDIR/$TOP_PATCH) \
    > $L_TMP/log 2>&1 && L_REVERSE=1
  [[ $((L_FORWARD + L_REVERSE)) -eq 1 ]]
}
assert "$TOP_PATCH is consistent with $AOSP_WORK_GENERIC_16" \
  reverse_or_forward_applies

# The patch applies to the pristine file (HEAD of device/google/atv) and adds
# the launcher.
top_patch_applies_to_head() {
  local L_F=products/sdk_atv_x86.mk
  local L_DIR=$L_TMP/pristine/device/google/atv
  mkdir -p $L_DIR/products
  git -C $AOSP_WORK_GENERIC_16/device/google/atv show HEAD:$L_F \
    > $L_DIR/$L_F || return 1
  (cd $L_TMP/pristine && patch -p0 -f -N -F0 < $PATCHDIR/$TOP_PATCH) \
    > /dev/null && grep -q TvSampleLeanbackLauncher $L_DIR/$L_F
}
assert "the patch applies to HEAD of device/google/atv" top_patch_applies_to_head

finish
