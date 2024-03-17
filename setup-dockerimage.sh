#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

ARG_DIST_CODENAME=focal
ARG_UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --apt           : Set apt repository url
    --apt)
    ARG_UBUNTU_APT_URL=$2
    shift
    ;;
    ##  --apt-country   : Set apt repository url
    --apt-country)
    ARG_UBUNTU_APT_URL=http://$2.archive.ubuntu.com/ubuntu/
    shift
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" $THIS_SCRIPT | sed -e "s/^ *##//"
    exit 0
    ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done


cd $(dirname $0)

docker build -t env-aosp/$ARG_DIST_CODENAME:latest \
  --build-arg DIST_CODENAME=$ARG_DIST_CODENAME \
  --build-arg UBUNTU_APT_URL=$ARG_UBUNTU_APT_URL \
  ./base

