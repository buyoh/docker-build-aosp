#!/bin/bash

# Tests for src/preprocess.sh sourced via src/start.sh

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Copy src to emulate /tmp/src in the container, and add a dummy task.
cp -r $REPODIR/src $L_TMP/src
cat > $L_TMP/src/dummy.sh <<'EOT'
set -eu
source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh
echo "SCRIPTDIR=$SCRIPTDIR"
echo "PWD=$PWD"
echo "OUTDIR=$OUTDIR"
echo "LUNCH_CHOICE=$LUNCH_CHOICE"
EOT
sed -i 's/build|patch|fetch|patch-revert)/build|patch|fetch|patch-revert|dummy)/' $L_TMP/src/start.sh
mkdir -p $L_TMP/aosp $L_TMP/stub

# Stub git and mkdir of /mnt/out
cat > $L_TMP/stub/git <<'EOT'
#!/bin/sh
exit 0
EOT
chmod +x $L_TMP/stub/git

# usage: run_start [<ARG_RPI> [<ARG_PLATFORM> [<ARG_FORM_FACTOR>]]]
run_start() {
  (
    export PATH=$L_TMP/stub:$PATH
    export ARG_ANDROID_VERSION=14 ARG_RPI=${1-rpi4} ARG_ARCH= ARG_NO_GEN=true
    export ARG_PLATFORM=${2-} ARG_FORM_FACTOR=${3-}
    export CONTAINER_SRCDIR=$L_TMP/aosp
    mkdir() { :; }
    export -f mkdir
    cd /
    bash $L_TMP/src/start.sh dummy
  ) > $L_TMP/log 2>/dev/null
}

assert "start.sh runs a task with preprocess.sh" run_start
assert "SCRIPTDIR is the src directory" grep -qx "SCRIPTDIR=$L_TMP/src" $L_TMP/log
assert "cwd is CONTAINER_SRCDIR" grep -qx "PWD=$L_TMP/aosp" $L_TMP/log
assert "OUTDIR is set" grep -qx "OUTDIR=/mnt/out/android-14-arm64" $L_TMP/log
assert "config is loaded" grep -qx "LUNCH_CHOICE=rpi4_tv-userdebug" $L_TMP/log

# OUTDIR gets a suffix for each axis that differs from the default.
outdir_is() {
  local L_EXPECTED=$1
  shift
  run_start "$@" && grep -qx "OUTDIR=/mnt/out/$L_EXPECTED" $L_TMP/log
}
assert "OUTDIR: rpi4 tv" outdir_is android-14-arm64 rpi4 rpi4 tv
assert "OUTDIR: non-rpi default" outdir_is android-14-x86_64 ""
assert "OUTDIR: cuttlefish tv" outdir_is android-14-x86_64 "" cuttlefish tv
assert "OUTDIR: auto" outdir_is android-14-x86_64-auto "" "" auto
assert "OUTDIR: emulator" outdir_is android-14-x86_64-emulator "" emulator
assert "OUTDIR: emulator auto" \
  outdir_is android-14-x86_64-emulator-auto "" emulator auto
assert "non-rpi lunch" run_start "" emulator auto
assert "non-rpi lunch is loaded" \
  grep -qx "LUNCH_CHOICE=sdk_car_x86_64-trunk_staging-eng" $L_TMP/log

finish
