# Overview of the manifest/ directory

This directory contains the list of Kubernetes resources needed to deploy a real POC version of the TimescaleDB + Prometheus/Postresql exporter resources.

## General Notes

The `remote_write` configuration only grabs a very small subset of available Prometheus metrics. Note: In the case of Openshift, multiple Prometheus replicas are deployed by default, which can lead to series duplication, which may not be an actual concern if those values eventually average out. My understanding is there's no way to utilize the thanos-querier query interface layer, at least in the current, released versions of the monitoring stack.

Utilizing the PrometheusRules custom resources is highly, highly recommended due to the potentially heavy memory utilization of the exporter. Without scraping metrics that have been pre-computed, which is the case of metrics that are in a particular rule group, you risk the exporter getting evicted from nodes due to an ever expanding heap. Digging into the pprof report locally would suggest that the constant unmarshalling of Prometheus labels is a source of pain points, and the current implementation is preventing objects from being properly garbage collected by Go. In the case you attempt to set memory resource limits on the exporter, you getting into a state where the exporter is consistently reporting an OOMKilled status as kubelet is killing that process whenever the memory consumption has been reached it's configured limit.

Extending the out-of-the-box Postgresql views/available metrics scraped from Prometheus isn't the greatest UX at the moment. In order to do this, you can either update the remote_write configuration in the openshift-cluster-monitoring ConfigMap, or updating the list of Prometheus `metering.rules` rules that get deployed as a part of the monitoring manifest resources.

## Limitations

- The exporter and database containers are deployed separately as Pods. In the future, it makes more sense to have the exporter as a sidecar container in the same Pod as the TimescaleDB database.
- PVC backs up the entire /var/lib/postgresql/data directory. I've read but haven't really deep dived into whether it's necessary to have a dedicated volume for the WAL records.
- No general recommendations for resource requests or limits for either of the Pods.
- When deploying on Openshift, the `anyuid` scc needs to be added to the default ServiceAccount in the namespace those resources are present. There's probably a better workaround for this, like checking what's an appropriate fsGroup configuration, but this will do the trick.
