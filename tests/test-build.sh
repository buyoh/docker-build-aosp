#!/bin/bash

# Tests for the non-RPi part of src/container/build.sh (make targets, copying
# outputs and build-info.json) with a fake AOSP tree. lunch and m are stubs.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Emulate /tmp/src in the container (src/host is not passed).
mkdir -p $L_TMP/src
cp -r $REPODIR/src/container $REPODIR/src/common $L_TMP/src/
mkdir -p $L_TMP/stub
cat > $L_TMP/stub/git <<'EOT'
#!/bin/sh
exit 0
EOT
chmod +x $L_TMP/stub/git

# usage: setup_tree [with-launcher|launcher-only|no-kernel-mk]
#   (none)        : no generic patch
#   with-launcher : the generic patch is applied (sdk_atv_x86.mk and the
#                   goldfish x86_64.mk)
#   launcher-only : only sdk_atv_x86.mk is patched (a workdir patched by an
#                   older version of the tool)
#   no-kernel-mk  : sdk_atv_x86.mk is patched, but x86_64.mk does not exist
setup_tree() {
  rm -rf $L_TMP/aosp $L_TMP/mnt_out $L_TMP/m.log
  mkdir -p $L_TMP/aosp/build $L_TMP/mnt_out
  local L_PRODUCT=$L_TMP/aosp/out/target/product/fake
  local L_HOST=$L_TMP/aosp/out/host/linux-x86
  mkdir -p $L_PRODUCT $L_HOST
  cat > $L_TMP/aosp/build/envsetup.sh <<EOT
lunch() {
  export ANDROID_PRODUCT_OUT=$L_PRODUCT
  export ANDROID_HOST_OUT=$L_HOST
  echo "lunch \$*" >> $L_TMP/m.log
  # Read it in a child process: Kati sees only exported variables.
  bash -c 'echo "TARGET_KERNEL_USE=\${TARGET_KERNEL_USE:-}"' >> $L_TMP/m.log
}
m() {
  echo "m \$*" >> $L_TMP/m.log
}
EOT
  printf 'boot.img\nsuper.img\n' > $L_PRODUCT/required_images
  for L_F in boot.img super.img android-info.txt \
             sdk-repo-linux-system-images.zip; do
    echo $L_F > $L_PRODUCT/$L_F
  done
  echo tar > $L_HOST/cvd-host_package.tar.gz
  mkdir -p $L_TMP/aosp/device/google/atv/products
  echo "PRODUCT_NAME := sdk_atv_x86" \
    > $L_TMP/aosp/device/google/atv/products/sdk_atv_x86.mk
  local L_KERNEL_MK=$L_TMP/aosp/device/generic/goldfish/board/kernel/x86_64.mk
  mkdir -p $(dirname $L_KERNEL_MK)
  echo 'TARGET_KERNEL_USE ?= 6.6' > $L_KERNEL_MK
  case "${1:-}" in
    with-launcher|launcher-only|no-kernel-mk)
      echo "PRODUCT_PACKAGES += TvSampleLeanbackLauncher" \
        >> $L_TMP/aosp/device/google/atv/products/sdk_atv_x86.mk
      ;;
  esac
  case "${1:-}" in
    with-launcher)
      echo '# (build-aosp-rpi)' >> $L_KERNEL_MK ;;
    no-kernel-mk)
      rm $L_KERNEL_MK ;;
  esac
}

# usage: run_build <ARG_PLATFORM> <ARG_FORM_FACTOR>
# T_VERSION / T_ARCH: the android version and the arch (default: 14, none)
run_build() {
  local L_OPTS=(--android ${T_VERSION:-14} --no-rpi --no-gen)
  if [[ -n "${T_ARCH:-}" ]]; then L_OPTS+=(--arch $T_ARCH); fi
  if [[ -n "$1" ]]; then L_OPTS+=(--platform $1); fi
  if [[ -n "$2" ]]; then L_OPTS+=(--form-factor $2); fi
  make_config $L_TMP/config.json $L_TMP/aosp "${L_OPTS[@]}" || return 1
  (
    export PATH=$L_TMP/stub:$PATH
    export TEST_MNT_OUT=$L_TMP/mnt_out
    cd /
    bash $L_TMP/src/container/start.sh --resolved-config $L_TMP/config.json build
  ) > $L_TMP/log 2>&1
}

fails_build() {
  ! run_build "$@"
}

info_has() {
  local L_DIR=$1 L_KEY=$2 L_VALUE=$3
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get(sys.argv[2]) == sys.argv[3] else 1)
' $L_TMP/mnt_out/$L_DIR/build-info.json $L_KEY "$L_VALUE"
}

# cuttlefish
setup_tree
L_OUT=$L_TMP/mnt_out/android-14-x86_64
mkdir -p $L_OUT/images
echo old > $L_OUT/images/old.img
assert "cuttlefish: build succeeds" run_build "" ""
assert "cuttlefish: lunch" grep -qx "lunch aosp_cf_x86_64_tv-trunk_staging-eng" $L_TMP/m.log
assert "cuttlefish: make targets" grep -qx "m droid hosttar" $L_TMP/m.log
for L_F in boot.img super.img android-info.txt; do
  assert "cuttlefish: images/$L_F" test -f $L_OUT/images/$L_F
done
assert "cuttlefish: old images are removed" test ! -e $L_OUT/images/old.img
assert "cuttlefish: host package" test -f $L_OUT/cvd-host_package.tar.gz
assert "cuttlefish: build-info.json platform" info_has android-14-x86_64 platform cuttlefish
assert "cuttlefish: build-info.json form_factor" info_has android-14-x86_64 form_factor tv
assert "cuttlefish: build-info.json lunch" \
  info_has android-14-x86_64 lunch_choice aosp_cf_x86_64_tv-trunk_staging-eng
assert "cuttlefish: build-info.json android_version" info_has android-14-x86_64 android_version 14
assert "cuttlefish: no warning of non-RPi" bash -c "! grep -q 'not implemented' $L_TMP/log"

# cuttlefish: a missing required_images fails without build-info.json
setup_tree
rm $L_TMP/aosp/out/target/product/fake/required_images
mkdir -p $L_TMP/mnt_out/android-14-x86_64-auto
echo '{}' > $L_TMP/mnt_out/android-14-x86_64-auto/build-info.json
assert "cuttlefish: no required_images fails" fails_build cuttlefish auto
assert "cuttlefish: the stale build-info.json is removed" \
  test ! -e $L_TMP/mnt_out/android-14-x86_64-auto/build-info.json

# cuttlefish: a missing image fails
setup_tree
rm $L_TMP/aosp/out/target/product/fake/super.img
mkdir -p $L_TMP/mnt_out/android-14-x86_64-phone
echo '{}' > $L_TMP/mnt_out/android-14-x86_64-phone/build-info.json
assert "cuttlefish: a missing image fails" fails_build cuttlefish phone
assert "cuttlefish: the failure leaves no build-info.json (missing image)" \
  test ! -e $L_TMP/mnt_out/android-14-x86_64-phone/build-info.json

# emulator
setup_tree
L_OUT=$L_TMP/mnt_out/android-14-x86_64-emulator-phone
assert "emulator: build succeeds" run_build emulator phone
assert "emulator: make targets" grep -qx "m droid emu_img_zip" $L_TMP/m.log
assert "emulator: zip" test -f $L_OUT/sdk-repo-linux-system-images.zip
assert "emulator: no images" test ! -e $L_OUT/images
assert "emulator: build-info.json" info_has android-14-x86_64-emulator-phone platform emulator

# emulator/tv requires the generic patch
setup_tree
assert "emulator/tv: fails without the generic patch" fails_build emulator tv
assert "emulator/tv: the message" grep -q "requires the generic patch" $L_TMP/log
assert "emulator/tv: m is not run" test ! -e $L_TMP/m.log
setup_tree with-launcher
assert "emulator/tv: succeeds with the generic patch" run_build emulator tv
assert "emulator/tv: lunch" grep -qx "lunch sdk_atv_x86-trunk_staging-eng" $L_TMP/m.log
assert "emulator/tv: the 6.1 kernel" grep -qx "TARGET_KERNEL_USE=6.1" $L_TMP/m.log
# The patch of an older version of the tool (only sdk_atv_x86.mk).
setup_tree launcher-only
assert "emulator/tv: fails without the goldfish patch" fails_build emulator tv
assert "emulator/tv: the message of the goldfish patch" \
  grep -q "requires the generic patch for device/generic/goldfish/board/kernel/x86_64.mk. Run the 'patch' task" $L_TMP/log
assert "emulator/tv: m is not run (goldfish patch)" test ! -e $L_TMP/m.log
setup_tree no-kernel-mk
assert "emulator/tv: fails without x86_64.mk" fails_build emulator tv
assert "emulator/tv: the message of no x86_64.mk" \
  grep -q "x86_64.mk not found. Run the 'fetch' task" $L_TMP/log
assert "emulator/tv: m is not run (no x86_64.mk)" test ! -e $L_TMP/m.log
# The check and the kernel are only for emulator/tv.
setup_tree
assert "cuttlefish/tv: does not require the generic patch" run_build cuttlefish tv
assert "cuttlefish/tv: the default kernel" grep -qx "TARGET_KERNEL_USE=" $L_TMP/m.log
setup_tree launcher-only
assert "emulator/phone: does not require the goldfish patch" run_build emulator phone
assert "emulator/phone: the default kernel" grep -qx "TARGET_KERNEL_USE=" $L_TMP/m.log

# Android 16: the tool has no goldfish patch for 16 (the upstream pins the
# kernel of the TV emulator), so only the atv patch is checked.
android_16() {
  local T_VERSION=16
  run_build "$@"
}
fails_16() {
  ! android_16 "$@"
}
setup_tree
assert "16 emulator/tv: fails without the generic patch" fails_16 emulator tv
assert "16 emulator/tv: the message" grep -q "emulator/tv requires the generic patch. Run" $L_TMP/log
assert "16 emulator/tv: m is not run" test ! -e $L_TMP/m.log
setup_tree launcher-only
assert "16 emulator/tv: succeeds without the goldfish patch" android_16 emulator tv
assert "16 emulator/tv: lunch" grep -qx "lunch sdk_atv_x86-bp4a-eng" $L_TMP/m.log
assert "16 emulator/tv: no TARGET_KERNEL_USE" grep -qx "TARGET_KERNEL_USE=" $L_TMP/m.log
assert "16 emulator/tv: make targets" grep -qx "m droid emu_img_zip" $L_TMP/m.log
assert "16 emulator/tv: zip" test -f $L_TMP/mnt_out/android-16-x86_64-emulator/sdk-repo-linux-system-images.zip
assert "16 emulator/tv: build-info.json android_version" \
  info_has android-16-x86_64-emulator android_version 16
assert "16 emulator/tv: build-info.json lunch" \
  info_has android-16-x86_64-emulator lunch_choice sdk_atv_x86-bp4a-eng
setup_tree no-kernel-mk
assert "16 emulator/tv: the goldfish x86_64.mk is not needed" android_16 emulator tv
# 14 still checks the goldfish patch (the same tree fails for 14).
setup_tree launcher-only
assert "14 emulator/tv: still requires the goldfish patch" fails_build emulator tv
setup_tree
assert "16 cuttlefish: build succeeds" android_16 "" ""
assert "16 cuttlefish: lunch" grep -qx "lunch aosp_cf_x86_64_tv-bp4a-eng" $L_TMP/m.log
assert "16 cuttlefish: make targets" grep -qx "m droid hosttar" $L_TMP/m.log
assert "16 cuttlefish: images" test -f $L_TMP/mnt_out/android-16-x86_64/images/super.img
assert "16 cuttlefish: host package" test -f $L_TMP/mnt_out/android-16-x86_64/cvd-host_package.tar.gz

# Android 10-12 for non-RPi: m only, no copy and no build-info.json
android_12() {
  local T_VERSION=12 T_ARCH=x86_64
  run_build "" ""
}
setup_tree
assert "12 non-rpi: build succeeds" android_12
assert "12 non-rpi: make has no targets" grep -qx "m " $L_TMP/m.log
assert "12 non-rpi: the warning of non-RPi" grep -q "not implemented" $L_TMP/log
assert "12 non-rpi: no build-info.json" \
  test ! -e $L_TMP/mnt_out/android-12-x86_64/build-info.json

finish
