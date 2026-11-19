#!/bin/bash

set -eux

# The resolved config (start.sh).
L_BUILD_CONFIG=${1:-}
source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

exec bash
