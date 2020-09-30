FROM openshift/origin-release:golang-1.15 AS builder

WORKDIR /promscale
COPY ./pkg ./pkg
COPY ./cmd ./cmd
COPY ./go.mod ./go.mod
COPY ./go.sum ./go.sum
COPY ./vendor ./vendor

ENV GO111MODULE="on"

# TODO: do the actual building of the binary in Makefile target
RUN CGO_ENABLED=0 \
    go build -a --mod=vendor --ldflags '-w' \
    -o /go/promscale ./cmd/promscale

FROM centos:8
USER 3001
COPY --from=builder /go/promscale /
ENTRYPOINT ["/promscale"]
