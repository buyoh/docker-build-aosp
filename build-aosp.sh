#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

DIST_CODENAME=focal
USER_=${SUDO_USER:-${USER:-$(whoami)}}

ARG_ADDUSER=false
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
    ##  --adduser       : Add the user in the docker container before running the
    ##                  : docker container. This feature is useful when you use
    ##                  : non rootless-docker.
    --adduser)
    ARG_ADDUSER=true
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
    ## available tasks: fetch, patch, build, patch-revert
    ##  fetch           : Fetch sources from the repository
    ##  patch           : Apply patches
    ##  build           : Build sources
    ##  patch-revert    : Revert patches
    build|patch|fetch|patch-revert)
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

if [[ -z "$ARG_TASKS" ]]; then
  echo "No task is specified."
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

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

OPTIONS=" \
  --env ARG_ANDROID_VERSION=$ARG_ANDROID_VERSION \
  --env ARG_ARCH=$ARG_ARCH \
  -v $SCRIPTDIR/src:/opt/mnt_src \
  -v $WORK_SOURCEDIR:/mnt/work \
  -v $WORK_GENDIR:/mnt/gen \
  -v $WORK_OUTDIR:/mnt/out \
  -w /tmp/$USER_/ \
"

if [[ "$ARG_ADDUSER" == "true" ]]; then
  OPTIONS="$OPTIONS --env USER_=$USER_ --env UID_=$UID_ --env GID_=$GID_ "
fi

DOCKER_OPTIONS="-it "
COMMAND_REDIRECTS=""

if [[ "$ARG_RUNAS_DAEMON" == "true" ]]; then
  DOCKER_OPTIONS="-d "
  COMMAND_REDIRECTS="2>&1 | tee /mnt/out/console-$TIMESTAMP.log"
fi

# Commonize the user namespace
DOCKER_OPTIONS="$DOCKER_OPTIONS --userns=host --privileged "

exec docker run \
  --init --rm $DOCKER_OPTIONS $OPTIONS \
  env-aosp/$DIST_CODENAME:latest \
  "cp -ar /opt/mnt_src /tmp/src && bash /tmp/src/start.sh $ARG_TASKS $COMMAND_REDIRECTS"
