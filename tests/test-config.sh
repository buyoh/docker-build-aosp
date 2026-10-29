#!/bin/bash

# Tests for src/config/android-*.sh

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

# Source the config in a subshell and print the given variables.
# usage: run_config <version> <ARG_RPI> <ARG_ARCH> <vars...>
run_config() {
  local L_VERSION=$1 L_RPI=$2 L_ARCH=$3
  shift 3
  (
    set -eu
    ARG_RPI=$L_RPI
    ARG_ARCH=$L_ARCH
    # android-10.sh modifies /usr/bin/python for non-RPi.
    ln() { :; }
    source $REPODIR/src/config/android-$L_VERSION.sh > /dev/null
    for L_VAR in "$@"; do
      echo -n "${!L_VAR} "
    done
  )
}

expect() {
  local L_EXPECTED=$1
  shift
  local L_ACTUAL
  L_ACTUAL=$(run_config "$@" 2>/dev/null)
  if [[ "${L_ACTUAL% }" != "$L_EXPECTED" ]]; then
    echo "  expected: '$L_EXPECTED', actual: '${L_ACTUAL% }'"
    return 1
  fi
}

fails() {
  ! run_config "$@" > /dev/null 2>&1
}

assert "14 rpi: kernel branch and dist" \
  expect "arpi14-6.1.62 arpi14-6.1" 14 rpi4 "" BRANCH_KERNEL_RPI KERNEL_DIST_DIR
assert "12 rpi: kernel branch and dist" \
  expect "arpi-5.10 arpi-5.10" 12 rpi4 "" BRANCH_KERNEL_RPI KERNEL_DIST_DIR
assert "14 rpi: lunch" expect "rpi4_tv-userdebug" 14 rpi4 "" LUNCH_CHOICE
assert "14 non-rpi: lunch" \
  expect "aosp_cf_x86_64_tv-trunk_staging-eng" 14 "" x86_64 LUNCH_CHOICE
for L_V in 10 11 12; do
  assert "$L_V rpi: lunch" expect "rpi4-eng" $L_V rpi4 "" LUNCH_CHOICE
  assert "$L_V non-rpi: lunch" expect "aosp_x86_64-eng" $L_V "" x86_64 LUNCH_CHOICE
done
assert "14 rpi: default arch" expect "arm64" 14 rpi4 "" ARCH
assert "10 rpi: arm is allowed" expect "arm" 10 rpi4 arm ARCH
assert "11 rpi: arm is allowed" expect "arm" 11 rpi4 arm ARCH

for L_V in 10 11 12 14; do
  assert "$L_V: unknown arch fails" fails $L_V rpi4 aarch64 ARCH
done
assert "12 rpi: arm fails" fails 12 rpi4 arm ARCH
assert "14 rpi: arm fails" fails 14 rpi4 arm ARCH
assert "10 rpi: x86_64 fails" fails 10 rpi4 x86_64 ARCH
assert "11 rpi: x86_64 fails" fails 11 rpi4 x86_64 ARCH
assert "10 non-rpi: x86_64 is allowed" expect "x86_64" 10 "" x86_64 ARCH
assert "14 rpi: x86_64 fails" fails 14 rpi4 x86_64 ARCH

finish
