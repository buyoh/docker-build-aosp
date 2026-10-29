#!/bin/bash

# Tests for build-aosp.sh with a stub docker command.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

mkdir -p $L_TMP/stub $L_TMP/var $L_TMP/out
# The stub saves the last argument (the command in the container).
# "test -e" checks exit with $STUB_TEST_RC.
cat > $L_TMP/stub/docker <<'EOT'
#!/bin/bash
for L_LAST in "$@"; do :; done
if [[ "$L_LAST" == "test -e "* ]]; then
  exit ${STUB_TEST_RC:-1}
fi
echo "$L_LAST" > $STUB_OUT
EOT
chmod +x $L_TMP/stub/docker

run_build_aosp() {
  PATH=$L_TMP/stub:$PATH STUB_OUT=$L_TMP/command \
    bash $REPODIR/build-aosp.sh --rpi --android 14 \
      --workdir $L_TMP/var --outdir $L_TMP/out "$@" > $L_TMP/log 2>&1
}

# Run the command saved by the stub with a fake start.sh in the host.
# usage: run_container_command <exit code of start.sh>
run_container_command() {
  local L_RC=$1
  rm -rf $L_TMP/fake && mkdir -p $L_TMP/fake/mnt_src $L_TMP/fake/out
  printf 'echo running\nexit %s\n' $L_RC > $L_TMP/fake/mnt_src/start.sh
  local L_CMD
  L_CMD=$(sed -e "s#/opt/mnt_src#$L_TMP/fake/mnt_src#g" \
              -e "s#/tmp/src#$L_TMP/fake/src#g" \
              -e "s#/mnt/out#$L_TMP/fake/out#g" $L_TMP/command)
  # Run it through the entrypoint of the docker image (without --adduser).
  (unset USER_ UID_ GID_; sh $REPODIR/base/entrypoint.sh "$L_CMD") > /dev/null 2>&1
}

exit_code_is() {
  local L_EXPECTED=$1 L_ACTUAL
  shift
  "$@"
  L_ACTUAL=$?
  [[ $L_ACTUAL -eq $L_EXPECTED ]] || { echo "  expected $L_EXPECTED, actual $L_ACTUAL"; return 1; }
}

fails() {
  ! "$@"
}

# --daemon: the exit code of start.sh is propagated through tee
assert "daemon: build-aosp.sh runs docker" run_build_aosp --daemon build
assert "daemon: the output is logged by tee" grep -q '| tee /mnt/out/console-' $L_TMP/command
assert "daemon: failure of start.sh is propagated" exit_code_is 3 run_container_command 3
assert "daemon: success of start.sh is propagated" exit_code_is 0 run_container_command 0
assert "daemon: the log is written" bash -c "grep -q running $L_TMP/fake/out/console-*.log"
assert "daemon: the exit status is logged (success)" bash -c "grep -qx 'exit status: 0' $L_TMP/fake/out/console-*.log"
run_container_command 3
assert "daemon: the exit status is logged (failure)" bash -c "grep -qx 'exit status: 3' $L_TMP/fake/out/console-*.log"

# foreground
assert "foreground: build-aosp.sh runs docker" run_build_aosp build
assert "foreground: failure of start.sh is propagated" exit_code_is 3 run_container_command 3

# --mount-same
mkdir -p $L_TMP/var/work
# usage: run_mount_same <exit code of "test -e" in the container>
run_mount_same() {
  (export STUB_TEST_RC=$1; run_build_aosp --mount-same build)
}
assert "mount-same: not used in the container" run_mount_same 1
assert "mount-same: already used in the container" fails run_mount_same 0
assert "mount-same: already used is reported" grep -q "already in use" $L_TMP/log
assert "mount-same: docker failure stops" fails run_mount_same 125
assert "mount-same: docker failure is reported" grep -q "Failed to run the docker image" $L_TMP/log

finish
