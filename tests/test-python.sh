#!/bin/bash

# Run the python tests (tests/py). They do not need docker.
# Set TEST_IN_IMAGE=1 to run them also with the python of the docker image
# (env-aosp/focal:latest), if the image exists.

set -u

REPODIR=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)
IMAGE=env-aosp/focal:latest

cd $REPODIR
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=src/host:src/common \
  python3 -m unittest discover -s tests/py -t tests/py
L_RC=$?

if [[ "${TEST_IN_IMAGE:-}" == 1 ]]; then
  if docker image inspect $IMAGE > /dev/null 2>&1; then
    echo "=== in $IMAGE"
    docker run --rm --pull=never -v "$REPODIR:/w:ro" $IMAGE \
      "cd /w && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=src/host:src/common python3 -m unittest discover -s tests/py -t tests/py" \
      || L_RC=1
  else
    echo "skip: $IMAGE does not exist"
  fi
fi

exit $L_RC
