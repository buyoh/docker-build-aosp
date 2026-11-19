#!/bin/bash

# Tests for src/container/preprocess.sh sourced via src/container/start.sh

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Copy src/container and src/common to emulate /tmp/src in the container
# (src/host is not passed), and add a dummy task.
mkdir -p $L_TMP/src
cp -r $REPODIR/src/container $REPODIR/src/common $L_TMP/src/
cat > $L_TMP/src/container/dummy.sh <<'EOT'
set -eu
source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh
echo "SCRIPTDIR=$SCRIPTDIR"
echo "PWD=$PWD"
echo "OUTDIR=$OUTDIR"
echo "LUNCH_CHOICE=$LUNCH_CHOICE"
env > $(dirname $(dirname $SCRIPTDIR))/env.txt
EOT
# The resolved config is read once by start.sh: a task that removes it does
# not affect the next task.
cat > $L_TMP/src/container/dummyrm.sh <<'EOT'
set -eu
source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh
rm -f "$L_BUILD_CONFIG"
echo "REMOVED"
EOT
sed -i 's/build|patch|fetch|patch-revert)/build|patch|fetch|patch-revert|dummy|dummyrm)/' $L_TMP/src/container/start.sh
mkdir -p $L_TMP/aosp $L_TMP/stub

# Stub git and mkdir of /mnt/out
cat > $L_TMP/stub/git <<'EOT'
#!/bin/sh
exit 0
EOT
chmod +x $L_TMP/stub/git

# usage: run_start [<rpi4 or ""> [<platform> [<form factor>]]]
# T_VERSION: the android version (default: 14)
run_start() {
  local L_OPTS=(--android ${T_VERSION:-14} --no-gen)
  if [[ -n "${1-rpi4}" ]]; then L_OPTS+=(--rpi); else L_OPTS+=(--no-rpi); fi
  if [[ -n "${2-}" ]]; then L_OPTS+=(--platform "$2"); fi
  if [[ -n "${3-}" ]]; then L_OPTS+=(--form-factor "$3"); fi
  make_config $L_TMP/config.json $L_TMP/aosp "${L_OPTS[@]}" || return 1
  (
    export PATH=$L_TMP/stub:$PATH
    mkdir() { :; }
    ln() { echo "LN: $*" >> $L_TMP/ln.txt; }
    export -f mkdir ln
    export L_TMP
    rm -f $L_TMP/env.txt $L_TMP/ln.txt
    cd /
    bash $L_TMP/src/container/start.sh --resolved-config $L_TMP/config.json dummy
  ) > $L_TMP/log 2>/dev/null
}

assert "start.sh runs a task with preprocess.sh" run_start
assert "SCRIPTDIR is the src/container directory" grep -qx "SCRIPTDIR=$L_TMP/src/container" $L_TMP/log
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


# The exported variables come from the resolved config (config_env.py).
exported() {
  grep -qx "$1" $L_TMP/env.txt
}
not_exported() {
  ! grep -q "^$1=" $L_TMP/env.txt
}
run_start "" emulator tv
assert "emulator/tv: TARGET_KERNEL_USE" exported TARGET_KERNEL_USE=6.1
assert "emulator/tv: ARG_RPI is exported empty" exported ARG_RPI=
assert "emulator/tv: ARG_PLATFORM is resolved" exported ARG_PLATFORM=emulator
assert "emulator/tv: ALLOW_NINJA_ENV" exported ALLOW_NINJA_ENV=1
assert "emulator/tv: no SKIP_ABI_CHECKS" not_exported SKIP_ABI_CHECKS
assert "emulator/tv: LUNCH_CHOICE is not exported" not_exported LUNCH_CHOICE
assert "emulator/tv: REPO_REV is not exported" not_exported REPO_REV
run_start rpi4
assert "rpi 14: SKIP_ABI_CHECKS" exported SKIP_ABI_CHECKS=true
assert "rpi 14: ARG_RPI" exported ARG_RPI=rpi4
assert "rpi 14: CROSS_COMPILE" exported CROSS_COMPILE=aarch64-linux-gnu-
assert "rpi 14: no TARGET_KERNEL_USE" not_exported TARGET_KERNEL_USE
assert "rpi 14: BRANCH_KERNEL_RPI" exported BRANCH_KERNEL_RPI=arpi14-6.1.62
run_start "" cuttlefish tv
assert "cuttlefish/tv: no TARGET_KERNEL_USE" not_exported TARGET_KERNEL_USE
assert "cuttlefish/tv: no SKIP_ABI_CHECKS" not_exported SKIP_ABI_CHECKS
assert "cuttlefish/tv: no python2 link" test ! -e $L_TMP/ln.txt

android_10() {
  local T_VERSION=10
  run_start "$@"
}
assert "10 non-rpi: runs" android_10 ""
assert "10 non-rpi: python is python2" \
  grep -qx "LN: -sf /usr/bin/python2 /usr/bin/python" $L_TMP/ln.txt
assert "10 non-rpi: no BRANCH_KERNEL_RPI" not_exported BRANCH_KERNEL_RPI
assert "10 non-rpi: OUTDIR" grep -qx "OUTDIR=/mnt/out/android-10-arm" $L_TMP/log
assert "10 rpi: runs" android_10 rpi4
assert "10 rpi: no python2 link" test ! -e $L_TMP/ln.txt

# Without a valid resolved config, nothing runs.
fails_start() {
  ! (
    export PATH=$L_TMP/stub:$PATH
    cd /
    bash $L_TMP/src/container/start.sh "$@"
  ) > $L_TMP/log 2>&1
}
assert "no --resolved-config fails" fails_start dummy
assert "the message of no --resolved-config" \
  grep -q "error: usage: start.sh --resolved-config" $L_TMP/log
assert "--resolved-config without a path fails" fails_start --resolved-config
assert "no task fails" fails_start --resolved-config $L_TMP/config.json
assert "the message of no task" \
  grep -q "error: usage: start.sh --resolved-config" $L_TMP/log
echo '{"schema": 99}' > $L_TMP/bad.json
assert "an invalid resolved config fails" \
  fails_start --resolved-config $L_TMP/bad.json dummy
assert "the message of an invalid resolved config" \
  grep -q "error: Invalid resolved config .*unsupported schema" $L_TMP/log
assert "the dummy task is not run" bash -c "! grep -q '^LUNCH_CHOICE=' $L_TMP/log"

# The config is read once.
make_config $L_TMP/config.json $L_TMP/aosp --android 14 --no-gen --rpi
read_once() {
  (
    export PATH=$L_TMP/stub:$PATH
    mkdir() { :; }
    export -f mkdir
    cd /
    bash $L_TMP/src/container/start.sh --resolved-config $L_TMP/config.json dummyrm dummy
  ) > $L_TMP/log 2>&1
}
assert "the config is read once" read_once
assert "the config was removed by the first task" test ! -e $L_TMP/config.json
assert "the second task has the config" \
  grep -qx "LUNCH_CHOICE=rpi4_tv-userdebug" $L_TMP/log

# The bash task gets the resolved config too.
make_config $L_TMP/config.json $L_TMP/aosp --android 14 --no-gen --rpi
bash_task() {
  (
    export PATH=$L_TMP/stub:$PATH
    mkdir() { :; }
    export -f mkdir
    cd /
    # The interactive shell (exec bash) reads the command from stdin.
    echo 'echo "IN_BASH ARCH=$ARCH ARG_PLATFORM=$ARG_PLATFORM"' \
      | bash $L_TMP/src/container/start.sh --resolved-config $L_TMP/config.json bash
  ) > $L_TMP/log 2>&1
}
assert "bash task runs" bash_task
assert "bash task has the config" grep -qx "IN_BASH ARCH=arm64 ARG_PLATFORM=rpi4" $L_TMP/log

finish
