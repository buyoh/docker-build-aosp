# Decide the platform and the form factor. Sourced by android-*.sh after
# ANDROID_VERSION is set. It defines PLATFORM_DEFAULT and FORM_FACTOR_DEFAULT
# (used by preprocess.sh for OUTDIR), and exports ARG_PLATFORM and
# ARG_FORM_FACTOR with the defaults applied.
# Keep the checks and their order the same as resolve() in
# src/aosp_build/versions.py (tests/py/test_versions_parity.py).

if [[ -n "${ARG_RPI:-}" ]]; then
  PLATFORM_DEFAULT=rpi4
elif [[ $ANDROID_VERSION -ge 14 ]]; then
  PLATFORM_DEFAULT=cuttlefish
else
  # aosp_x86_64 of Android 10-12 is goldfish (the Android Emulator).
  PLATFORM_DEFAULT=emulator
fi
if [[ -n "${ARG_RPI:-}" ]] || [[ $ANDROID_VERSION -ge 14 ]]; then
  FORM_FACTOR_DEFAULT=tv
else
  FORM_FACTOR_DEFAULT=phone
fi

export ARG_PLATFORM=${ARG_PLATFORM:-$PLATFORM_DEFAULT}
export ARG_FORM_FACTOR=${ARG_FORM_FACTOR:-$FORM_FACTOR_DEFAULT}

case "$ARG_PLATFORM" in
  rpi4|cuttlefish|emulator) ;;
  *)
    echo "error: unsupported platform: $ARG_PLATFORM" >&2
    exit 2
    ;;
esac
case "$ARG_FORM_FACTOR" in
  phone|tv|auto) ;;
  *)
    echo "error: unsupported form factor: $ARG_FORM_FACTOR" >&2
    exit 2
    ;;
esac

# ARG_RPI and ARG_PLATFORM are inconsistent if they are given directly (not by
# build-aosp.sh).
if { [[ -n "${ARG_RPI:-}" ]] && [[ "$ARG_PLATFORM" != rpi4 ]]; } || \
   { [[ -z "${ARG_RPI:-}" ]] && [[ "$ARG_PLATFORM" == rpi4 ]]; }; then
  echo "error: ARG_RPI and ARG_PLATFORM are inconsistent" >&2
  exit 2
fi

if [[ $ANDROID_VERSION -lt 14 ]]; then
  if [[ "$ARG_PLATFORM" != "$PLATFORM_DEFAULT" ]] || \
     [[ "$ARG_FORM_FACTOR" != "$FORM_FACTOR_DEFAULT" ]]; then
    echo "error: Android $ANDROID_VERSION supports only $PLATFORM_DEFAULT/$FORM_FACTOR_DEFAULT" >&2
    exit 2
  fi
fi
