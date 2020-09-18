#! /bin/bash

set -e

: "${KUBECONFIG:?}"

NAMESPACE=${1:-${METERING_NAMESPACE}}

oc --namespace=${NAMESPACE} exec -it $(oc --namespace=${NAMESPACE} get pods -l  app=timescaledb --no-headers | awk '{ print $1 }') -- psql --username=testuser --dbname=metering
