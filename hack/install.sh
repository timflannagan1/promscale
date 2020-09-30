#! /bin/bash

set -eou pipefail

: "${KUBECONFIG:?}"

ROOT_DIR=$(dirname "${BASH_SOURCE[0]}")/..

export NAMESPACE=${1:-tflannag}
export MONITORING_NAMESPACE=${MONITORING_NAMESPACE:=openshift-monitoring}
export MANIFEST_DIR=${MANIFEST_DIR:=${ROOT_DIR}/manifests}

if ! oc get ns ${NAMESPACE} >/dev/null 2>&1; then
    echo "Creating the ${NAMESPACE} namespace"
    oc create ns ${NAMESPACE}
fi

echo "Adding the 'anyuid' SCC to the Postgres ServiceAccount"
oc -n ${NAMESPACE} adm policy add-scc-to-user anyuid -z postgres


#
# General Connector Resources
#
if ! oc -n ${NAMESPACE} get sa postgres >/dev/null 2>&1; then
    echo "Creating the exporter Service"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/sa.yaml
fi

if ! oc -n ${NAMESPACE} get role ${NAMESPACE}-service-account >/dev/null 2>&1; then
    echo "Creating the exporter Service"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/role.yaml
fi

if ! oc -n ${NAMESPACE} get rolebinding ${NAMESPACE}-service-account >/dev/null 2>&1; then
    echo "Creating the exporter Service"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/role_binding.yaml
fi


#
# Create the TimescaleDB resources
#
if ! oc -n ${NAMESPACE} get deployment timescaledb >/dev/null 2>&1; then
    echo "Creating the TimescaleDB Deployment"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/db/deployment.yaml
fi

if ! oc -n ${NAMESPACE} get service timescaledb >/dev/null 2>&1; then
    echo "Creating the TimescaleDB Service"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/db/service.yaml
fi

export CLUSTER_IP=$(oc -n ${NAMESPACE} get services/timescaledb -o jsonpath='{.spec.clusterIP}')
while [[ $? != 0 ]]; do
    echo "Waiting for the 'timescaledb' Service to have a populated spec.ClusterIP"
    export CLUSTER_IP=$(oc -n ${NAMESPACE} get services/timescaledb --jsonpath='{.spec.clusterIP}')
done

#
# Create the postgres exporter resources
#
if ! oc -n ${NAMESPACE} get deployment exporter >/dev/null 2>&1; then
    echo "Creating the exporter Deployment"
    envsubst < ${MANIFEST_DIR}/timescale/exporter/deployment.yaml | oc -n ${NAMESPACE} apply -f -
fi

if ! oc -n ${NAMESPACE} get service exporter >/dev/null 2>&1; then
    echo "Creating the exporter Service"
    oc -n ${NAMESPACE} apply -f ${MANIFEST_DIR}/timescale/exporter/service.yaml
fi

#
# Create the monitoring resources
#
if ! oc -n ${MONITORING_NAMESPACE} get configmap cluster-monitoring-operator >/dev/null 2>&1; then
    echo "Creating the cluster-monitoring-operator ConfigMap"
    envsubst < ${MANIFEST_DIR}/monitoring/configmap.yaml | oc -n ${MONITORING_NAMESPACE} apply -f -
fi

if ! oc -n ${MONITORING_NAMESPACE} get prometheusrules metering >/dev/null 2>&1; then
    echo "Creating the metering PrometheusRule custom resource"
    oc -n ${MONITORING_NAMESPACE} apply -f ${MANIFEST_DIR}/monitoring/rules.yaml
fi
