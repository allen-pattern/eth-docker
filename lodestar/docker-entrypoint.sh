#!/usr/bin/env bash

if [ "$(id -u)" = '0' ]; then
  chown -R lsconsensus:lsconsensus /var/lib/lodestar
  exec su-exec lsconsensus docker-entrypoint.sh "$@"
fi

# Remove old low-entropy token, related to Sigma Prime security audit
# This detection isn't perfect - a user could recreate the token without ./ethd update
if [[ -f /var/lib/lodestar/consensus/api-token.txt  && "$(date +%s -r /var/lib/nimbus/api-token.txt)" -lt "$(date +%s --date="2023-05-02 09:00:00")" ]]; then
    rm /var/lib/lodestar/consensus/api-token.txt
fi

if [ ! -f /var/lib/lodestar/consensus/api-token.txt ]; then
    __token=api-token-0x$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
    echo "$__token" > /var/lib/lodestar/consensus/api-token.txt
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/lodestar/consensus/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ -O "/var/lib/lodestar/consensus/ee-secret" ]]; then
  # In case someone specificies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/lodestar/consensus/ee-secret
fi
if [[ -O "/var/lib/lodestar/consensus/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/lodestar/consensus/ee-secret/jwtsecret
fi

# Check whether we should use MEV Boost
if [ "${MEV_BOOST}" = "true" ]; then
  __mev_boost="--builder --builder.urls=${MEV_NODE:-http://mev-boost:18550}"
  echo "MEV Boost enabled"
else
  __mev_boost=""
fi

# Check whether we should send stats to beaconcha.in
if [ -n "${BEACON_STATS_API}" ]; then
  __beacon_stats="--monitoring.endpoint https://beaconcha.in/api/v1/client/metrics?apikey=${BEACON_STATS_API}&machine=${BEACON_STATS_MACHINE}"
  echo "Beacon stats API enabled"
else
  __beacon_stats=""
fi

# Check whether we should rapid sync
if [ -n "${RAPID_SYNC_URL}" ]; then
  if [ "${ARCHIVE_NODE}" = "true" ]; then
    echo "Lodestar archive node cannot use checkpoint sync: Syncing from genesis."
    __rapid_sync=""
  else
    __rapid_sync="--checkpointSyncUrl=${RAPID_SYNC_URL}"
    echo "Checkpoint sync enabled"
  fi
else
  __rapid_sync=""
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${__mev_boost} ${__beacon_stats} ${__rapid_sync} ${CL_EXTRAS}
