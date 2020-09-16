#!/usr/bin/env bash

set -euf -o pipefail

SCRIPT_DIR=$(pwd)
ROOT_DIR=$(dirname ${SCRIPT_DIR})
CONNECTOR_URL="localhost:9201"
PROM_URL="localhost:9090"

CONF=$(mktemp)

chmod 777 $CONF

echo "scrape_configs:
  - job_name: 'connector'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9201']
remote_read:
- url: http://$CONNECTOR_URL/read
  remote_timeout: 1m
  read_recent: true

remote_write:
- url: http://$CONNECTOR_URL/write
  remote_timeout: 1m" > $CONF

docker run --rm --name e2e-tsdb -p 5432:5432/tcp -e "POSTGRES_PASSWORD=postgres" timescale/timescaledb:latest-pg12  > /dev/null 2>&1 &
docker run --rm --name e2e-prom --network="host" -p 9090:9090/tcp -v "$CONF:/etc/prometheus/prometheus.yml" prom/prometheus:latest > /dev/null 2>&1  &

cd $ROOT_DIR/cmd/timescale-prometheus
go get ./...
go build .

# wait for DB to start receiving connections
sleep 5

TS_PROM_LOG_LEVEL=debug \
TS_PROM_DB_CONNECT_RETRIES=10 \
TS_PROM_DB_PASSWORD=postgres \
TS_PROM_DB_NAME=postgres \
TS_PROM_DB_SSL_MODE=disable \
TS_PROM_WEB_TELEMETRY_PATH=/metrics \
./timescale-prometheus &

CONN_PID=$!

trap "kill $CONN_PID; docker stop e2e-tsdb; docker stop e2e-prom; rm $CONF" EXIT


# the race condition between the connector and the test runner is real
# to ensure that the connector is actually started, we wait twice hpoing
# that will be long enough that the connector is really started
wait_for_connector() {
    echo "waiting for connector"

    sleep 10

    ${SCRIPT_DIR}/wait-for.sh ${CONNECTOR_URL} -t 60 -- echo "connector may be ready..."

    sleep 10

    ${SCRIPT_DIR}/wait-for.sh ${CONNECTOR_URL} -t 60 -- echo "connector ready"
}

wait_for_connector
START_TIME=$(date +"%s")

echo "sending write request"

curl -v \
    -H "Content-Type: application/x-protobuf" \
    -H "Content-Encoding: snappy" \
    -H "X-Prometheus-Remote-Write-Version: 0.1.0" \
    --data-binary "@${SCRIPT_DIR}/real-dataset.sz" \
    "${CONNECTOR_URL}/write"

EXIT_CODE=0

compare_connector_and_prom() {
    QUERY=${1}
    CONNECTOR_OUTPUT=$(curl "http://${CONNECTOR_URL}/api/v1/${QUERY}")
    PROM_OUTPUT=$(curl "http://${PROM_URL}/api/v1/${QUERY}")
    echo "ran: ${QUERY}"
    echo " connector response: ${CONNECTOR_OUTPUT}"
    echo "prometheus response: ${PROM_OUTPUT}"
    if [ "${CONNECTOR_OUTPUT}" != "${PROM_OUTPUT}" ]; then
        echo "mismatched output"
        exit 1
    fi
}
END_TIME=$(date +"%s")

DATASET_START_TIME="2020-08-10T10:35:20Z"
DATASET_END_TIME="2020-08-10T11:43:50Z"


# Check that backfilled dataset is present in both sources.
compare_connector_and_prom "query_range?query=demo_disk_usage_bytes%7Binstance%3D%22demo.promlabs.com%3A10002%22%7D&start=$DATASET_START_TIME&end=$DATASET_END_TIME&step=30s"
compare_connector_and_prom "query?query=demo_cpu_usage_seconds_total%7Binstance%3D%22demo.promlabs.com%3A10000%22%2Cmode%3D%22user%22%7D&time=$DATASET_START_TIME"
# Check that connector metrics are scraped.
compare_connector_and_prom "query?query=ts_prom_received_samples_total&time=$START_TIME"
# Check that connector is up.
compare_connector_and_prom "query?query=up&time=$START_TIME"
# Check series endpoint matches on connector series.
compare_connector_and_prom "series?match%5B%5D=ts_prom_sent_samples_total"


# Labels endpoint cannot be compared to Prometheus becuase it will always differ due to direct backfilling of the real dataset.
# We have to compare it to the correct expected output.

EXPECTED_OUTPUT='{"status":"success","data":["__name__","code","handler","instance","job","le","method","mode","path","quantile","status","version"]}'
LABELS_OUTPUT=$(curl "http://${CONNECTOR_URL}/api/v1/labels")
echo "  labels response: ${LABELS_OUTPUT}"
echo "expected response: ${EXPECTED_OUTPUT}"

if [ "${LABELS_OUTPUT}" != "${EXPECTED_OUTPUT}" ]; then
    echo "mismatched output"
    exit 1
fi

exit 0
