#!/bin/bash

# Static checks for shell scripts.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

for L_FILE in $REPODIR/*.sh $REPODIR/src/*.sh $REPODIR/src/config/*.sh \
              $REPODIR/src/patches/*.sh; do
  assert "syntax: ${L_FILE#$REPODIR/}" bash -n $L_FILE
done

for L_TASK in bash build fetch patch patch-revert; do
  assert "$L_TASK.sh sources preprocess.sh" \
    grep -q '^source .*/preprocess.sh$' $REPODIR/src/$L_TASK.sh
done

# Print the file with continuation lines joined.
joined() {
  sed -e ':a' -e '/\\$/N; s/\\\n//; ta' $1
}

assert "fetch.sh uses BRANCH_KERNEL_RPI" \
  bash -c "$(declare -f joined); joined $REPODIR/src/fetch.sh | grep -q 'kernel_manifest *-b \$BRANCH_KERNEL_RPI'"
assert "fetch.sh has no hard-coded kernel branch" \
  bash -c "$(declare -f joined); ! joined $REPODIR/src/fetch.sh | grep -q 'kernel_manifest *-b [^\$]'"
assert "build.sh has no hard-coded kernel dist directory" \
  bash -c "! grep -q 'out/arpi-' $REPODIR/src/build.sh"
assert "build.sh does not regenerate ABI reference dumps" \
  bash -c "! grep -q 'create_reference_dumps' $REPODIR/src/build.sh"
# lunch unsets BUILD_VAR_CACHE_READY, and get_build_var fails under set -u.
assert "build.sh does not use get_build_var" \
  bash -c "! grep -qE '^[^#]*get_build_var' $REPODIR/src/build.sh"
for L_TASK in patch patch-revert; do
  assert "$L_TASK.sh uses the generic patch set for non-RPi" \
    grep -q 'patcher.sh .*--set generic' $REPODIR/src/$L_TASK.sh
done
assert "Dockerfile pins the base image digest" \
  grep -q '^FROM .*@\$UBUNTU_DIGEST$' $REPODIR/base/Dockerfile
assert "Dockerfile pins pip packages" \
  bash -c "grep 'pip3 install' $REPODIR/base/Dockerfile | grep -q 'meson==.*ninja=='"
# build-aosp.sh: see tests/py/test_host.py (--pull=never).

assert "clean-after-apt.sh does not use brace expansion (run by dash)" \
  bash -c "! grep -q '{.*,.*}' $REPODIR/base/clean-after-apt.sh"

# A hunk without a file header is silently dropped by GNU patch.
has_header_before_first_hunk() {
  awk '/^\+\+\+ /{ok = 1} /^@@/{exit !ok}' $1
}
for L_FILE in $REPODIR/src/patches/android-*.patch; do
  assert "${L_FILE#$REPODIR/} has a file header before the first hunk" \
    has_header_before_first_hunk $L_FILE
done

finish
