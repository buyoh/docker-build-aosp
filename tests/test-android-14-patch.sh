#!/bin/bash

# Tests for src/common/patches/android-14.patch against the real AOSP tree.
# This test is skipped if AOSP_WORK is not set. It does not modify the tree.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

if [[ -z "${AOSP_WORK:-}" ]]; then
  echo "skip: AOSP_WORK is not set"
  exit 0
fi

PATCHFILE=$REPODIR/src/common/patches/android-14.patch
L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# The patch is fully applied to the tree (or fully not applied).
reverse_or_forward_applies() {
  (cd $AOSP_WORK && \
    { patch -p0 -f -N -R --dry-run < $PATCHFILE || \
      patch -p0 -f -N --dry-run < $PATCHFILE; }) > $L_TMP/log 2>&1
}
assert "android-14.patch is consistent with $AOSP_WORK" reverse_or_forward_applies

# device/arpi/rpi4 changes apply to the pristine device tree.
device_patch_applies_to_head() {
  local L_DEV=device/arpi/rpi4
  mkdir -p $L_TMP/pristine/$L_DEV
  for L_F in AndroidProducts.mk BoardConfig.mk; do
    git -C $AOSP_WORK/$L_DEV show HEAD:$L_F > $L_TMP/pristine/$L_DEV/$L_F || return 1
  done
  awk '/^--- /{p = ($0 ~ /device\/arpi\/rpi4/ || $0 ~ /\/dev\/null/)} p' \
    $PATCHFILE > $L_TMP/device.patch
  (cd $L_TMP/pristine && patch -p0 -f -N < $L_TMP/device.patch) > /dev/null && \
    [[ -f $L_TMP/pristine/$L_DEV/rpi4_tv.mk ]]
}
assert "device/arpi/rpi4 hunks apply to HEAD" device_patch_applies_to_head

lunch_choice_is_defined() {
  grep -q "rpi4_tv-userdebug" $L_TMP/pristine/device/arpi/rpi4/AndroidProducts.mk
}
assert "patched AndroidProducts.mk defines rpi4_tv-userdebug" lunch_choice_is_defined

finish
