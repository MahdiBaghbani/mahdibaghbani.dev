FROM golang:1.22.5-alpine3.20 AS builder

ARG REPO_GOATCOUNTER=https://github.com/zgoat/goatcounter
ARG BRANCH_BRANCH=release-2.5
ARG CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

RUN apk add --update --no-cache git build-base

RUN git clone --depth 1 --branch ${BRANCH_BRANCH} ${REPO_GOATCOUNTER}

RUN cd goatcounter && go build -tags osusergo,netgo,sqlite_omit_load_extension -ldflags="-X zgo.at/goatcounter/v2.Version=$(git log -n1 --format='%h_%cI') -extldflags=-static" ./cmd/goatcounter

FROM alpine:3.20 AS runner

# keys for oci taken from:
# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.title="Mahdi Baghbani goatcounter Image"
LABEL org.opencontainers.image.source="https://github.com/MahdiBaghbani/mahdibaghbani.dev"
LABEL org.opencontainers.image.authors="Mohammad Mahdi Baghbani Pourvahid"

# environment variables.
ENV GOATCOUNTER_LISTEN "'0.0.0.0:80'"
ENV GOATCOUNTER_DB "sqlite:///goatcounter/db/goatcounter.sqlite3?_busy_timeout=200&_journal_mode=wal&cache=shared"
ENV GOATCOUNTER_SMTP ""

WORKDIR /goatcounter

RUN apk add --update --no-cache ca-certificates
RUN addgroup -S goatcounter && adduser -S goatcounter -G goatcounter
RUN mkdir -p /goatcounter/db && chown -R goatcounter:goatcounter /goatcounter

USER goatcounter

COPY --chown=goatcounter:goatcounter --from=builder                             /go/goatcounter/goatcounter /usr/bin/goatcounter
COPY --chown=goatcounter:goatcounter ./docker/scripts/goatcounter.sh            /goatcounter/goatcounter.sh
COPY --chown=goatcounter:goatcounter ./docker/entrypoints/goatcounter.sh        /entrypoint.sh

VOLUME ["/goatcounter/db"]
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/goatcounter/goatcounter.sh"]
