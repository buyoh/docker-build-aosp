#!/bin/bash

# Tests for src/check-upstream.sh. git is replaced with a fake, so that the
# network is not needed. The script is copied to use fixture manifests.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_C=cccccccccccccccccccccccccccccccccccccccc
SHA_D=dddddddddddddddddddddddddddddddddddddddd

L_ROOT="$L_TMP/ro ot"
mkdir -p $L_TMP/bin "$L_ROOT/src/config" "$L_ROOT/src/manifests"
cp $REPODIR/src/check-upstream.sh "$L_ROOT/src/"
export FAKE_REFS=$L_TMP/refs
export FAKE_LOG=$L_TMP/git.log

# "git ls-remote <url> <ref>" prints what is registered in FAKE_REFS.
cat > $L_TMP/bin/git <<'EOL'
#!/bin/bash
echo "$*" >> $FAKE_LOG
[[ "$1" == ls-remote ]] || exit 99
[[ -n "${FAKE_OFFLINE:-}" ]] && exit 128
[[ -n "${FAKE_OFFLINE_FOR:-}" && "$2" == *"$FAKE_OFFLINE_FOR" ]] && exit 128
while read -r L_URL L_REF L_SHA; do
  if [[ "$L_URL" == "$2" && "$L_REF" == "$3" ]]; then
    printf '%s\t%s\n' "$L_SHA" "$L_REF"
  fi
done < $FAKE_REFS
exit 0
EOL
chmod +x $L_TMP/bin/git

GH=https://github.com/android-rpi

cat > "$L_ROOT"/src/config/upstream.sh <<EOL
UPSTREAM_WIKI_REV=$SHA_A
EOL

MAIN_MANIFEST=$(cat <<EOL
<manifest>
  <remote name="aosp" fetch=".."/>
  <remote name="arpi" fetch="https://github.com/android-rpi"/>
  <remote name="other" fetch="https://example.com/x"/>
  <default remote="aosp" revision="refs/tags/android-14.0.0_r17"/>
  <project path="build/soong" name="platform/build/soong" revision="$SHA_A" upstream="refs/tags/android-14.0.0_r17"/>
  <project path="device/arpi/rpi4" name="device_arpi_rpi4" remote="arpi" revision="$SHA_A" upstream="arpi-14"/>
  <project path="frameworks/av" name="frameworks_av" remote="arpi" revision="$SHA_B" upstream="refs/heads/arpi14-pi4"/>
  <project path="pinned" name="sha_only" remote="arpi" revision="$SHA_A"/>
  <project path="x" name="foreign" remote="other" revision="$SHA_A" upstream="main"/>
</manifest>
EOL
)
KERNEL_MANIFEST=$(cat <<EOL
<manifest>
  <remote name="arpi" fetch="."/>
  <remote name="aosp" fetch=".."/>
  <default remote="arpi"/>
  <project path="common" name="kernel_arpi" revision="$SHA_C" upstream="arpi14-6.1.62"/>
  <project path="configs" name="kernel/configs" remote="aosp" revision="$SHA_C" upstream="master"/>
</manifest>
EOL
)

write_fixtures() {
  rm -f "$L_ROOT"/src/manifests/*
  echo "$MAIN_MANIFEST" > "$L_ROOT"/src/manifests/android-14-pinned.xml
  echo "$KERNEL_MANIFEST" > "$L_ROOT"/src/manifests/android-14-kernel-pinned.xml
  cat > "$L_ROOT"/src/manifests/android-14.meta <<EOL
LOCAL_MANIFESTS_REV=$SHA_D
LOCAL_MANIFESTS_BRANCH=arpi14-pi4
KERNEL_MANIFEST_REV=$SHA_D
KERNEL_MANIFEST_BRANCH=arpi14-6.1.62
EOL
  cat > $FAKE_REFS <<EOL
$GH/device_arpi_rpi4 refs/heads/arpi-14 $SHA_A
$GH/frameworks_av refs/heads/arpi14-pi4 $SHA_B
$GH/kernel_arpi refs/heads/arpi14-6.1.62 $SHA_C
$GH/local_manifests refs/heads/arpi14-pi4 $SHA_D
$GH/kernel_manifest refs/heads/arpi14-6.1.62 $SHA_D
$GH/device_arpi_rpi4.wiki.git HEAD $SHA_A
EOL
}

run() {
  : > $FAKE_LOG
  PATH=$L_TMP/bin:$PATH bash "$L_ROOT"/src/check-upstream.sh "$@" > $L_TMP/log 2>&1
}

write_fixtures
run --android 14
assert "up to date: exit status" [ $? -eq 0 ]
assert "up to date: skips AOSP projects" bash -c "! grep -q 'build/soong\|googlesource' $FAKE_LOG"
assert "up to date: skips projects without upstream" bash -c "! grep -q sha_only $FAKE_LOG"
assert "up to date: skips remotes outside android-rpi" bash -c "! grep -q foreign $FAKE_LOG"
assert "up to date: skips .. remote of kernel_manifest" bash -c "! grep -q kernel/configs $FAKE_LOG"
assert "up to date: resolves relative fetch" grep -q "ls-remote $GH/kernel_arpi refs/heads/arpi14-6.1.62" $FAKE_LOG

write_fixtures
sed -i "s|frameworks_av refs/heads/arpi14-pi4 $SHA_B|frameworks_av refs/heads/arpi14-pi4 $SHA_C|" $FAKE_REFS
run --android 14
assert "project updated: exit status" [ $? -eq 1 ]
assert "project updated: shows the compare URL" \
  grep -q "$GH/frameworks_av/compare/$SHA_B...$SHA_C" $L_TMP/log

write_fixtures
sed -i "s|local_manifests refs/heads/arpi14-pi4 $SHA_D|local_manifests refs/heads/arpi14-pi4 $SHA_C|" $FAKE_REFS
run --android 14
assert "local_manifests updated: exit status" [ $? -eq 1 ]
assert "local_manifests updated: shows it" grep -q "local_manifests" $L_TMP/log

write_fixtures
sed -i "s|wiki.git HEAD $SHA_A|wiki.git HEAD $SHA_B|" $FAKE_REFS
run --android 14
assert "wiki updated: exit status" [ $? -eq 1 ]
assert "wiki updated: shows it" grep -q "wiki" $L_TMP/log

write_fixtures
sed -i "/frameworks_av/d" $FAKE_REFS
run --android 14
assert "branch removed: exit status" [ $? -eq 1 ]

# Android 11 has no kernel_manifest.
write_fixtures
sed -i '/^KERNEL_/d' "$L_ROOT"/src/manifests/android-14.meta
run --android 14
assert "meta without kernel: exit status" [ $? -eq 0 ]
assert "meta without kernel: not queried" bash -c "! grep -q kernel_manifest $FAKE_LOG"

write_fixtures
FAKE_OFFLINE=1 run --android 14
assert "git failure is not reported as up to date" [ $? -eq 3 ]

write_fixtures
sed -i "s|frameworks_av refs/heads/arpi14-pi4 $SHA_B|frameworks_av refs/heads/arpi14-pi4 $SHA_C|" $FAKE_REFS
FAKE_OFFLINE_FOR=device_arpi_rpi4 run --android 14
assert "partial git failure wins over a difference" [ $? -eq 3 ]

write_fixtures
sed -i '/^LOCAL_MANIFESTS_BRANCH/d' "$L_ROOT"/src/manifests/android-14.meta
run --android 14
assert "REV without BRANCH: exit status" [ $? -eq 2 ]

write_fixtures
sed -i 's/ upstream="[^"]*"//' "$L_ROOT"/src/manifests/android-14*-pinned.xml
run --android 14
assert "no project to compare is not up to date" [ $? -eq 2 ]

write_fixtures
sed -i '/^KERNEL_MANIFEST_REV/d' "$L_ROOT"/src/manifests/android-14.meta
run --android 14
assert "BRANCH without REV: exit status" [ $? -eq 2 ]

write_fixtures
sed -i '/^LOCAL_MANIFESTS_/d' "$L_ROOT"/src/manifests/android-14.meta
run --android 14
assert "local_manifests is required" [ $? -eq 2 ]

write_fixtures
sed -i 's/ upstream="[^"]*"//' "$L_ROOT"/src/manifests/android-14-kernel-pinned.xml
run --android 14
assert "a manifest without a project to compare is not up to date" [ $? -eq 2 ]

write_fixtures
run --android 12
assert "no pinned manifest: exit status" [ $? -eq 2 ]
assert "no pinned manifest: no network access" [ ! -s $FAKE_LOG ]

write_fixtures
rm "$L_ROOT"/src/manifests/android-14.meta
run --android 14
assert "no meta: exit status" [ $? -eq 2 ]

run --android
assert "--android without a value is rejected" [ $? -eq 2 ]
run
assert "--android is required" [ $? -eq 2 ]
run --android abc
assert "invalid --android is rejected" [ $? -eq 2 ]

assert "upstream.sh records the wiki revision" \
  grep -Eq '^UPSTREAM_WIKI_REV=[0-9a-f]{40}$' $REPODIR/src/config/upstream.sh

finish
