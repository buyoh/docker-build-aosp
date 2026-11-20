#!/bin/bash

# Static checks for shell scripts.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

for L_FILE in $REPODIR/*.sh $(find $REPODIR/src -name '*.sh' | sort); do
  assert "syntax: ${L_FILE#$REPODIR/}" bash -n $L_FILE
done
# Run by sh (dash) in the image.
for L_FILE in $REPODIR/docker/base/*.sh; do
  assert "syntax: ${L_FILE#$REPODIR/}" sh -n $L_FILE
done

# The layout of src/ by where the files run (AGENTS.md).
# Every tracked file is in src/host, src/container or src/common.
assert "src/ has only host/, container/ and common/" \
  bash -c "cd $REPODIR && ! git ls-files src | grep -vE '^src/(host|container|common)/'"
# src/host is not passed to the container. The paths in the container are
# relative ($SCRIPTDIR/../common) or under /tmp/src (/opt/mnt_src). Comments
# may name the files of src/host in the repository.
assert "src/container and src/common do not refer to src/host" \
  bash -c "cd $REPODIR && ! grep -rnE '\.\./host\b|/(tmp/src|opt/mnt_src)/host\b' src/container src/common"

# The files of src/common that src/container refers to by $SCRIPTDIR/../common
# (the same relative path in the repository and in /tmp/src of the container).
for L_REF in $(cd $REPODIR/src/container && grep -ohE '\$SCRIPTDIR/\.\./common/[^ ]+' *.sh | sort -u); do
  L_PATH=$REPODIR/src/container/${L_REF#\$SCRIPTDIR/}
  if [[ $L_PATH == *'$'* ]]; then
    # A path with a variable (e.g. the patch of $ANDROID_VERSION, which does
    # not exist for every version): the directory before the variable
    # exists, and the pattern matches at least one file.
    assert "src/container refers to an existing directory: $L_REF" \
      test -d "$(dirname "${L_PATH%%\$*}")"
    assert "src/container refers to an existing file pattern: $L_REF" \
      compgen -G "$(echo "$L_PATH" | sed -E 's/\$[A-Za-z_][A-Za-z0-9_]*/*/g')"
  else
    assert "src/container refers to an existing file: $L_REF" \
      test -f "$L_PATH"
  fi
done

for L_TASK in bash build fetch patch patch-revert; do
  assert "$L_TASK.sh sources preprocess.sh" \
    grep -q '^source .*/preprocess.sh$' $REPODIR/src/container/$L_TASK.sh
done

# Print the file with continuation lines joined.
joined() {
  sed -e ':a' -e '/\\$/N; s/\\\n//; ta' $1
}

assert "fetch.sh uses BRANCH_KERNEL_RPI" \
  bash -c "$(declare -f joined); joined $REPODIR/src/container/fetch.sh | grep -q 'kernel_manifest *-b \$BRANCH_KERNEL_RPI'"
assert "fetch.sh has no hard-coded kernel branch" \
  bash -c "$(declare -f joined); ! joined $REPODIR/src/container/fetch.sh | grep -q 'kernel_manifest *-b [^\$]'"
assert "build.sh has no hard-coded kernel dist directory" \
  bash -c "! grep -q 'out/arpi-' $REPODIR/src/container/build.sh"
assert "build.sh does not regenerate ABI reference dumps" \
  bash -c "! grep -q 'create_reference_dumps' $REPODIR/src/container/build.sh"
# lunch unsets BUILD_VAR_CACHE_READY, and get_build_var fails under set -u.
assert "build.sh does not use get_build_var" \
  bash -c "! grep -qE '^[^#]*get_build_var' $REPODIR/src/container/build.sh"
for L_TASK in patch patch-revert; do
  assert "$L_TASK.sh uses the generic patch set for non-RPi" \
    grep -q 'patcher.sh .*--set generic' $REPODIR/src/container/$L_TASK.sh
done
assert "Dockerfile pins the base image digest" \
  grep -q '^FROM .*@\$UBUNTU_DIGEST$' $REPODIR/docker/base/Dockerfile
assert "Dockerfile pins pip packages" \
  bash -c "grep 'pip3 install' $REPODIR/docker/base/Dockerfile | grep -q 'meson==.*ninja=='"
# build-aosp.sh: see tests/py/test_host.py (--pull=never).

assert "clean-after-apt.sh does not use brace expansion (run by dash)" \
  bash -c "! grep -q '{.*,.*}' $REPODIR/docker/base/clean-after-apt.sh"
assert "setup-dockerimage.sh builds the existing context docker/base" \
  bash -c "grep -q '^  \./docker/base$' $REPODIR/setup-dockerimage.sh && test -f $REPODIR/docker/base/Dockerfile"

# A hunk without a file header is silently dropped by GNU patch.
has_header_before_first_hunk() {
  awk '/^\+\+\+ /{ok = 1} /^@@/{exit !ok}' $1
}
# Including the patch files in subdirectories (applied in that directory).
for L_FILE in $(find $REPODIR/src/common/patches -name 'android-*.patch' | sort); do
  assert "${L_FILE#$REPODIR/} has a file header before the first hunk" \
    has_header_before_first_hunk $L_FILE
done

finish
