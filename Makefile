SHELL := /bin/bash

VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
            echo v0)

vendor:
	go mod tidy
	go mod vendor
	go mod verify

validate-manifest-rules:
	tail -n +6 manifests/monitoring/rules.yaml | promtool check rules /dev/stdin

validate-metering-rules:
	kubectl -n openshift-monitoring get prometheusrules metering -o yaml | faq -f yaml '.spec' | promtool check rules /dev/stdin
