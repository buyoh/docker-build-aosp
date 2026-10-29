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
assert "Dockerfile pins the base image digest" \
  grep -q '^FROM .*@\$UBUNTU_DIGEST$' $REPODIR/base/Dockerfile
assert "Dockerfile pins pip packages" \
  bash -c "grep 'pip3 install' $REPODIR/base/Dockerfile | grep -q 'meson==.*ninja=='"
# Join continuation lines and check every docker run command.
never_pulls() {
  local L_JOINED
  L_JOINED=$(joined $REPODIR/build-aosp.sh)
  [[ $(grep -c 'docker run' <<< "$L_JOINED") -gt 0 ]] && \
  [[ $(grep -c 'docker run' <<< "$L_JOINED") -eq \
     $(grep -c 'docker run *--rm --pull=never' <<< "$L_JOINED") ]]
}
assert "build-aosp.sh never pulls the image implicitly" never_pulls

assert "clean-after-apt.sh does not use brace expansion (run by dash)" \
  bash -c "! grep -q '{.*,.*}' $REPODIR/base/clean-after-apt.sh"

finish
