#!/bin/sh
set -e
die() {
  echo "$1" >&2
  exit 1
}
test -e /run/secrets/host.env || die "Missing host.env"

echo "DEBUG: host.env content:"
cat /run/secrets/host.env
echo "DEBUG: end content"

set -a
. /run/secrets/host.env
set +a

test -n "$DOCKER_HOST" || die "Missing DOCKER_HOST"
SOCAT_PID=
CREATED_SOCKET=0
if [ ! -e /var/run/docker.sock ]; then
  ulimit -n 1048576 2>/dev/null || true
  DOCKER_HOST_ADDRESS=${DOCKER_HOST#tcp://}
  test -n "$DOCKER_HOST_ADDRESS" || die "Missing DOCKER_HOST_ADDRESS"
  # This creates intermittent errors
  # trap 'kill $(jobs -p) 2>/dev/null' EXIT INT TERM
  socat -d0 UNIX-LISTEN:/var/run/docker.sock,fork,backlog=1024 TCP:$DOCKER_HOST_ADDRESS &
  SOCAT_PID=$!
  CREATED_SOCKET=1
fi
export DOCKER_HOST=unix:///var/run/docker.sock

if [ "$CREATED_SOCKET" -eq 1 ]; then
  if ! socat -u OPEN:/dev/null TCP:$DOCKER_HOST_ADDRESS,retry=10,interval=1 >/dev/null 2>&1; then
    die "Failed to connect to Docker host $DOCKER_HOST_ADDRESS"
  fi
  if ! socat -u OPEN:/dev/null UNIX-CONNECT:/var/run/docker.sock,retry=10,interval=1 >/dev/null 2>&1; then
    die "Failed to connect to /var/run/docker.sock"
  fi
fi

[ ! -e ~/.docker/config.json -a -n "$DOCKER_AUTH_CONFIG" ] && mkdir -p ~/.docker/ && echo "$DOCKER_AUTH_CONFIG" > ~/.docker/config.json
[ -e ~/.docker/config.json ] || die "Failed to create docker config json"

"$@"
CMD_EXIT=$?

SOCAT_EXIT=0
if [ -n "$SOCAT_PID" ]; then
  if kill -0 "$SOCAT_PID" 2>/dev/null; then
    kill "$SOCAT_PID" >/dev/null 2>&1 || true
    wait "$SOCAT_PID" >/dev/null 2>&1 || SOCAT_EXIT=$?
  else
    SOCAT_EXIT=1
  fi
fi

if [ $CMD_EXIT -ne 0 ]; then
  exit $CMD_EXIT
fi
if [ $SOCAT_EXIT -ne 0 ]; then
  echo "warn: socat tunnel exited unexpectedly" >&2
fi
exit 0
