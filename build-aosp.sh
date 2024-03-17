#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

DIST_CODENAME=focal
USER_=${USER:-$(whoami)}

ARG_RUNAS_DAEMON=false
ARG_ANDROID_VERSION=
ARG_ARCH=
ARG_LABEL=default
ARG_WORKDIR=
ARG_OUTDIR=
ARG_TASKS=

# =============================================================================

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --user          : The user instead of current user
    --user)
    USER_=$2
    shift
    ;;
    ##  --android       : The android version (10 or 11)
    --android)
    ARG_ANDROID_VERSION=$2
    shift
    ;;
    ##  --workdir       : The folder that store sources will be <WORKDIR>/<label>/work.
    --workdir)
    ARG_WORKDIR=$2
    shift
    ;;
    ##  --label         : The folder that store sources will be <workdir>/<label>/work
    ##                  : The default is 'default'.
    --label)
    ARG_LABEL=$2
    shift
    ;;
    ##  --outdir        : The directory that output binaries.
    --outdir)
    ARG_OUTDIR=$2
    shift
    ;;
    ##  --arch          : The taget architecture (arm or arm64)
    --arch)
    ARG_ARCH=$2
    shift
    ;;
    ##  --daemon        : Run the docker container as daemon
    --daemon)
    ARG_RUNAS_DAEMON=true
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...] task1 task2 ..."
    echo ""
    grep "^ *##" $THIS_SCRIPT | sed -e "s/^ *##//"
    exit 0
    ;;
    ## available tasks: fetch, build
    ##  fetch           : Fetch sources from the repository
    ##  build           : Build sources
    fetch|build)
    ARG_TASKS="$ARG_TASKS $arg"
    ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

UID_=$(id -u $USER_)
GID_=$(id -g $USER_)

if [[ "$ARG_ANDROID_VERSION" == "" ]]; then
  echo "--android is required. e.g. '10'."
  exit 2
fi

if [[ ! -f $(dirname $0)/src/config/android-$ARG_ANDROID_VERSION.sh ]]; then
  echo "The android version '$ARG_ANDROID_VERSION' is not supported."
  exit 2
fi

if [[ -z "$ARG_WORKDIR" ]]; then
  echo "--workdir is required."
  exit 2
fi
if [[ ! -d "$ARG_WORKDIR" ]]; then
  echo "The workdir '$ARG_WORKDIR' does not exist."
  exit 2
fi
ARG_WORKDIR=$(readlink -f "$ARG_WORKDIR")
if [[ ! -d "$ARG_WORKDIR" ]]; then
  echo "The workdir '$ARG_WORKDIR' does not exist."
  exit 2
fi

if [[ -z "$ARG_OUTDIR" ]]; then
  echo "--outdir is required."
  exit 2
fi
if [[ ! -d "$ARG_OUTDIR" ]]; then
  echo "The outdir '$ARG_OUTDIR' does not exist."
  exit 2
fi
ARG_OUTDIR=$(readlink -f "$ARG_OUTDIR")
if [[ ! -d "$ARG_OUTDIR" ]]; then
  echo "The outdir '$ARG_OUTDIR' does not exist."
  exit 2
fi

# =============================================================================

cd $(dirname $0)
SCRIPTDIR=$PWD

WORK_SOURCEDIR=$ARG_WORKDIR/$ARG_LABEL/work
WORK_GENDIR=$ARG_WORKDIR/$ARG_LABEL/gen
WORK_OUTDIR=$ARG_OUTDIR

# TODO: chown? chmod?
mkdir -p $WORK_SOURCEDIR
mkdir -p $WORK_GENDIR

# =============================================================================

OPTIONS=" \
  --env ARG_ANDROID_VERSION=$ARG_ANDROID_VERSION \
  --env ARG_ARCH=$ARG_ARCH \
  --env USER_=$USER_ --env UID_=$UID_ --env GID_=$GID_ \
  -v $SCRIPTDIR/src:/opt/mnt_src \
  -v $WORK_SOURCEDIR:/mnt/work \
  -v $WORK_GENDIR:/mnt/gen \
  -v $WORK_OUTDIR:/mnt/out \
  -w /tmp/$USER_/ \
"

DOCKER_OPTIONS="-it "

if [[ "$ARG_RUNAS_DAEMON" == "true" ]]; then
  DOCKER_OPTIONS="-d "
fi

exec docker run \
  --init --rm $DOCKER_OPTIONS $OPTIONS \
  env-aosp/$DIST_CODENAME:latest \
  "cp -ar /opt/mnt_src /tmp/src && bash /tmp/src/start.sh $ARG_TASKS 2>&1 | tee /mnt/out/console.log"
