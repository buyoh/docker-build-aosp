#!/bin/bash

# Check if the upstream (android-rpi) moved from the recorded revisions.
# Run on the host. This script does not need docker and changes nothing.
#
# exit status:
#   0: up to date
#   1: the upstream has been updated
#   2: invalid argument, or no valid record for the version
#   3: failed to access the upstream or to read the record

set -u

# A removed repository makes GitHub ask for credentials.
export GIT_TERMINAL_PROMPT=0

THIS_SCRIPT=$(readlink -f "$0")
SCRIPTDIR=$(dirname "$THIS_SCRIPT")
MANIFESTDIR=$SCRIPTDIR/src/common/manifests

UPSTREAM_URL=https://github.com/android-rpi
AOSP_MANIFEST_URL=https://android.googlesource.com/platform/manifest

ARG_ANDROID=

while [[ $# -gt 0 ]]
do
arg="$1"
case $arg in
    ##  --android       : Android version. e.g. 14
    --android)
    ARG_ANDROID=${2:-}
    shift $(($# > 1 ? 1 : 0))
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" "$THIS_SCRIPT" | sed -e "s/^ *##//"
    exit 0
    ;;
    *)
    echo "Unknown option $arg"
    exit 2
    ;;
esac
shift
done

if [[ ! "$ARG_ANDROID" =~ ^[0-9]+$ ]]; then
  echo "--android is required. e.g. --android 14"
  exit 2
fi

source "$SCRIPTDIR/src/host/upstream.sh"

METAFILE=$MANIFESTDIR/android-$ARG_ANDROID.meta
mapfile -t PINNED_FILES < <(compgen -G "$MANIFESTDIR/android-$ARG_ANDROID-*pinned.xml")

if [[ ${#PINNED_FILES[@]} -eq 0 ]] || [[ ! -f "$METAFILE" ]]; then
  echo "No pinned manifest for Android $ARG_ANDROID in '$MANIFESTDIR'."
  exit 2
fi

# Print "<name> <sha> <ref>" of the android-rpi projects following a branch.
list_projects() {
  python3 - "$1" "$2" "$UPSTREAM_URL/" <<'EOL'
import sys
import urllib.parse
import xml.etree.ElementTree as ET

manifest, manifest_url, upstream_url = sys.argv[1:]
root = ET.parse(manifest).getroot()
fetches = {r.get('name'): r.get('fetch') for r in root.findall('remote')}
default = root.find('default')
default_remote = default.get('remote') if default is not None else None

for project in root.findall('project'):
    fetch = fetches.get(project.get('remote', default_remote))
    upstream = project.get('upstream')
    if fetch is None or upstream is None:
        continue
    # A relative fetch is based on the URL of the manifest repository.
    url = urllib.parse.urljoin(manifest_url, fetch).rstrip('/') + '/'
    if url != upstream_url:
        continue
    if not upstream.startswith('refs/'):
        upstream = 'refs/heads/' + upstream
    print(project.get('name'), project.get('revision'), upstream)
EOL
}

get_meta() {
  sed -n "s/^$1=//p" "$METAFILE"
}

# Check a manifest repository recorded in the meta file.
# args: <repository name> <key prefix in the meta file> <required|optional>
check_manifest_repo() {
  local L_REV L_BRANCH
  L_REV=$(get_meta "$2_REV")
  L_BRANCH=$(get_meta "$2_BRANCH")
  if [[ -z "$L_REV" && -z "$L_BRANCH" && "$3" == optional ]]; then
    return
  fi
  if [[ -z "$L_REV" || -z "$L_BRANCH" ]]; then
    echo "$2_REV and $2_BRANCH must be recorded in '$METAFILE'."
    exit 2
  fi
  check_ref "$UPSTREAM_URL/$1" "refs/heads/$L_BRANCH" "$L_REV" "$UPSTREAM_URL/$1"
}

FOUND_DIFF=
FOUND_ERROR=

# Compare a recorded revision with the current one.
# args: <repository url> <ref> <recorded sha> <compare url prefix>
check_ref() {
  local L_OUTPUT L_HEAD
  if ! L_OUTPUT=$(git ls-remote "$1" "$2"); then
    echo "error: failed to access $1"
    FOUND_ERROR=1
    return
  fi
  L_HEAD=$(cut -f1 <<< "$L_OUTPUT")
  if [[ "$L_HEAD" == "$3" ]]; then
    return
  fi
  FOUND_DIFF=1
  echo "$1 ($2)"
  echo "  recorded: $3"
  echo "  current : ${L_HEAD:-(not found)}"
  if [[ -n "$L_HEAD" ]] && [[ -n "$4" ]]; then
    echo "  compare : $4/compare/$3...$L_HEAD"
  fi
}

for L_FILE in "${PINNED_FILES[@]}"; do
  if [[ "$L_FILE" == *-kernel-pinned.xml ]]; then
    L_MANIFEST_URL=$UPSTREAM_URL/kernel_manifest
  else
    L_MANIFEST_URL=$AOSP_MANIFEST_URL
  fi
  if ! L_PROJECTS=$(list_projects "$L_FILE" "$L_MANIFEST_URL"); then
    echo "error: failed to read $L_FILE"
    exit 3
  fi
  # Without "repo manifest -r", the manifest has no upstream attribute.
  if [[ -z "$L_PROJECTS" ]]; then
    echo "No android-rpi project following a branch in '$L_FILE'."
    exit 2
  fi
  while read -r L_NAME L_SHA L_REF; do
    if [[ -n "$L_NAME" ]]; then
      check_ref "$UPSTREAM_URL/$L_NAME" "$L_REF" "$L_SHA" "$UPSTREAM_URL/$L_NAME"
    fi
  done <<< "$L_PROJECTS"
done

# The manifest repositories themselves, to detect added or removed projects.
check_manifest_repo local_manifests LOCAL_MANIFESTS required
check_manifest_repo kernel_manifest KERNEL_MANIFEST optional

check_ref "$UPSTREAM_URL/device_arpi_rpi4.wiki.git" HEAD "$UPSTREAM_WIKI_REV" ""

if [[ -n "$FOUND_ERROR" ]]; then
  exit 3
fi
if [[ -n "$FOUND_DIFF" ]]; then
  exit 1
fi
echo "Android $ARG_ANDROID is up to date with the upstream."
