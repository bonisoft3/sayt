#!/bin/sh
set -e
die() {
  echo "$1" >&2
  exit 1
}
if [ -e /run/secrets/host.env ]; then
  set -a
  . /run/secrets/host.env
  set +a
fi
# host.env carries the daemon endpoint as DOCKER_HOST_TCP (a plain DOCKER_HOST
# would misdirect host-side CLIs that also source it).
DOCKER_HOST=${DOCKER_HOST:-$DOCKER_HOST_TCP}

SOCAT_PID=
CREATED_SOCKET=0
if [ ! -e /var/run/docker.sock ]; then
  test -n "$DOCKER_HOST" || die "docker socket unavailable"
  ulimit -n 1048576 2>/dev/null || true
  DOCKER_HOST_ADDRESS=${DOCKER_HOST#tcp://}
  test -n "$DOCKER_HOST_ADDRESS" || die "Missing DOCKER_HOST_ADDRESS"
  # This creates intermittent errors
  # trap 'kill $(jobs -p) 2>/dev/null' EXIT INT TERM
  socat -d0 UNIX-LISTEN:/var/run/docker.sock,fork,backlog=1024,reuseaddr TCP:$DOCKER_HOST_ADDRESS,keepalive,keepidle=30,keepintvl=15,keepcnt=4 &
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

[ ! -e ~/.docker/config.json ] && [ -n "$DOCKER_AUTH_CONFIG" ] && { mkdir -p ~/.docker/ && echo "$DOCKER_AUTH_CONFIG" > ~/.docker/config.json; }

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
