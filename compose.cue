package plugins_sayt

volumes: {
  "root-dot-task": {},
  "root-dot-cache": {},
  "root-dot-pkgx": {},
  "root-dot-gradle": {},
  "root-pnpm-store": {}
}

caches: [
  "${DIND:+/root/.task}${DIND:-root-dot-task}:/root/.task",
  "${DIND:+/root/.task}${DIND:-root-dot-cache}:/root/.cache",
  "${DIND:+/root/.pkgx}${DIND:-root-dot-pkgx}:/root/.pkgx",
  "${DIND:+/root/.gradle}${DIND:-root-dot-gradle}:/root/.gradle",
  "${DIND:+/root/.local/share/pnpm/store}${DIND:-root-pnpm-store}:/root/.local/share/pnpm/store"
]

build: {
	context:    "../.."
	dockerfile: string
	target:     string
	cache_from: ["type=gha,mode=min"]
	cache_to: ["type=gha,mode=min"]
}

debug: build & {
  target: "debug"
}

release: build &  {
  target: "release"
}

inception: {
  volumes: caches + [
	"//var/run/docker.sock:/var/run/docker.sock",
	//"${HOME:-~}/.kube:/root/.kube",
	//"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
  ]
  network_mode: "host"
  environment: ["TESTCONTAINERS_HOST_OVERRIDE=gateway.docker.internal"]
  // https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
  extra_hosts: [ "host.docker.internal:host-gateway", "gateway.docker.internal:host-gateway" ]
}

nointernet: {
  // https://stackoverflow.com/a/61243361
  dns: "0.0.0.0"
  // https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
  extra_hosts: [ "host.docker.internal:host-gateway" ]
}

services: {
	develop: inception & { command: string, build: debug }
	integrate: inception & { command: "sh -c 'socat TCP-LISTEN:2375,fork UNIX-CONNECT:/var/run/docker.sock& docker buildx build --add-host host.docker.internal:$(hostname -i) --add-host gateway.docker.internal:host-gateway --network host ../../ -f Dockerfile --no-cache --target integrate'", build: debug }
}
