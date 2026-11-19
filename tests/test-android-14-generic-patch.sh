#!/bin/bash

# Tests for the generic patches (src/common/patches/android-14-generic.patch
# and src/common/patches/device/generic/goldfish/android-14-generic.patch)
# against the real AOSP tree for non-RPi (android-14.0.0_r74). This test is skipped if
# AOSP_WORK_GENERIC is not set. It does not modify the tree.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

if [[ -z "${AOSP_WORK_GENERIC:-}" ]]; then
  echo "skip: AOSP_WORK_GENERIC is not set"
  exit 0
fi

# The generic patch files. A patch file in a subdirectory is applied in that
# directory (patcher.sh).
PATCHDIR=$REPODIR/src/common/patches
TOP_PATCH=android-14-generic.patch
GOLDFISH_PATCH=device/generic/goldfish/android-14-generic.patch
L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Each patch is fully applied to the tree or fully not applied, without fuzz
# and in exactly one direction (the same rule as patcher.sh).
reverse_or_forward_applies() {
  local L_PATCH=$1 L_DIR=$AOSP_WORK_GENERIC/$(dirname $1)
  local L_FORWARD=0 L_REVERSE=0
  (cd $L_DIR && patch -p0 -f -N -F0 --dry-run < $PATCHDIR/$L_PATCH) \
    > $L_TMP/log 2>&1 && L_FORWARD=1
  (cd $L_DIR && patch -p0 -f -N -F0 -R --dry-run < $PATCHDIR/$L_PATCH) \
    > $L_TMP/log 2>&1 && L_REVERSE=1
  [[ $((L_FORWARD + L_REVERSE)) -eq 1 ]]
}
for L_PATCH in $TOP_PATCH $GOLDFISH_PATCH; do
  assert "$L_PATCH is consistent with $AOSP_WORK_GENERIC" \
    reverse_or_forward_applies $L_PATCH
done

# <project> <file in the project> <patch>: apply the patch to the file of HEAD
# of the project in $L_TMP/pristine/<project>.
apply_to_head() {
  local L_PROJECT=$1 L_F=$2 L_PATCH=$3
  local L_DIR=$L_TMP/pristine/$L_PROJECT
  mkdir -p $L_DIR/$(dirname $L_F)
  git -C $AOSP_WORK_GENERIC/$L_PROJECT show HEAD:$L_F > $L_DIR/$L_F || return 1
  (cd $L_TMP/pristine/$(dirname $L_PATCH) && \
    patch -p0 -f -N -F0 < $PATCHDIR/$L_PATCH) > /dev/null
}

# The top-level patch applies to the pristine file and adds the launcher.
top_patch_applies_to_head() {
  apply_to_head device/google/atv products/sdk_atv_x86.mk $TOP_PATCH && \
    grep -q TvSampleLeanbackLauncher \
      $L_TMP/pristine/device/google/atv/products/sdk_atv_x86.mk
}
assert "the patch applies to HEAD of device/google/atv" top_patch_applies_to_head

# The goldfish patch applies to the pristine file, keeps only the existing
# ramdisk modules and has the mark that src/container/build.sh checks.
goldfish_patch_applies_to_head() {
  local L_F=$L_TMP/pristine/device/generic/goldfish/board/kernel/x86_64.mk
  apply_to_head device/generic/goldfish board/kernel/x86_64.mk \
    $GOLDFISH_PATCH && \
    grep -q 'build-aosp-rpi' $L_F && grep -qF '$(wildcard $(patsubst' $L_F
}
assert "the patch applies to HEAD of device/generic/goldfish" \
  goldfish_patch_applies_to_head

finish
