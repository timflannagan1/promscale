#! /bin/bash

set -eou pipefail

namespace=${1:-tflannag}

oc -n ${namespace} exec -it $(oc -n ${namespace} get po -l app=presto --no-headers | awk '{ print $1 }') -- \
    /usr/local/bin/presto-cli \
    --server http://presto:8080 \
    --catalog prometheus \
    --schema default \
    --execute 'show tables'
