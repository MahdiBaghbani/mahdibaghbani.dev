#!/usr/bin/env sh

set -e

OPTS="${OPTS} -listen ${GOATCOUNTER_LISTEN}"
OPTS="${OPTS} -tls http"
OPTS="${OPTS} -email-from ${GOATCOUNTER_EMAIL}"
OPTS="${OPTS} -db ${GOATCOUNTER_DB}"

if [ -n "${GOATCOUNTER_SMTP}" ]; then
  OPTS="${OPTS} -smtp ${GOATCOUNTER_SMTP}"
fi

if [ -n "$GOATCOUNTER_DEBUG" ]; then
  OPTS="${OPTS} -debug all"
fi

goatcounter serve -automigrate ${OPTS}
