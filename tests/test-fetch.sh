#!/bin/bash

# Tests for src/container/fetch.sh with a fake tree. repo and git are stubs
# that record their arguments; nothing is downloaded.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Emulate /tmp/src in the container (src/host is not passed).
mkdir -p $L_TMP/src
cp -r $REPODIR/src/container $REPODIR/src/common $L_TMP/src/
mkdir -p $L_TMP/stub
for L_CMD in repo git; do
  cat > $L_TMP/stub/$L_CMD <<EOT
#!/bin/sh
echo "$L_CMD \$*" >> $L_TMP/calls.log
exit 0
EOT
  chmod +x $L_TMP/stub/$L_CMD
done

setup_tree() {
  rm -rf $L_TMP/aosp $L_TMP/mnt_out $L_TMP/calls.log
  mkdir -p $L_TMP/aosp $L_TMP/mnt_out
}

# usage: run_fetch <build-aosp.sh option>...
run_fetch() {
  make_config $L_TMP/config.json $L_TMP/aosp --no-gen "$@" || return 1
  (
    export PATH=$L_TMP/stub:$PATH
    export TEST_MNT_OUT=$L_TMP/mnt_out
    cd /
    bash $L_TMP/src/container/start.sh --resolved-config $L_TMP/config.json fetch
  ) > $L_TMP/log 2>&1
}

fails_fetch() {
  ! run_fetch "$@"
}

repo_called() {
  grep -q "^repo $1" $L_TMP/calls.log
}

# Non-RPi: repo init (the tag of the version) and sync.
setup_tree
assert "16: fetch succeeds" run_fetch --android 16 --platform emulator --form-factor tv
assert "16: repo init with the tag" \
  grep -q "^repo init .* -b android-16.0.0_r4 " $L_TMP/calls.log
assert "16: repo sync" repo_called sync
assert "16: no local manifests" bash -c "! grep -q local_manifests $L_TMP/calls.log"

# Non-RPi with .repo/local_manifests (a workdir of RPi) fails before repo.
setup_tree
mkdir -p $L_TMP/aosp/.repo/local_manifests
assert "16: fails with .repo/local_manifests" \
  fails_fetch --android 16 --platform emulator --form-factor tv
assert "16: the message" grep -q "error: .repo/local_manifests exists, but this is a non-RPi build" $L_TMP/log
assert "16: repo is not run" bash -c "! test -e $L_TMP/calls.log || ! grep -q '^repo ' $L_TMP/calls.log"
# The same for 14 (the check does not depend on the version).
assert "14 non-RPi: fails with .repo/local_manifests" \
  fails_fetch --android 14 --platform cuttlefish
# A file (not a directory) is also rejected.
setup_tree
mkdir -p $L_TMP/aosp/.repo
touch $L_TMP/aosp/.repo/local_manifests
assert "16: fails with a file .repo/local_manifests" \
  fails_fetch --android 16 --platform emulator --form-factor tv

# RPi keeps its local manifests. 11 does not fetch the kernel
# (/mnt/kernel_work does not exist here).
setup_tree
mkdir -p $L_TMP/aosp/.repo/local_manifests
assert "11 RPi: fetch succeeds with .repo/local_manifests" \
  run_fetch --android 11 --rpi
assert "11 RPi: checks out the branch" \
  grep -q "^git -C .repo/local_manifests checkout arpi-11 -f" $L_TMP/calls.log
assert "11 RPi: repo sync" repo_called sync

finish
