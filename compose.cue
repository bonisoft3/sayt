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
}

build_debug: build & buildtime_inception & {
  target: "debug"
}

build_integrate: build & buildtime_inception & {
  target: "integrate"
}

build_release: build & {
  target: "release"
}

runtime_inception: {
  volumes: caches + [
	"//var/run/docker.sock:/var/run/docker.sock",
	//"${HOME:-~}/.kube:/root/.kube",
	//"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
  ]
  network_mode: "host"
  environment: ["TESTCONTAINERS_HOST_OVERRIDE=gateway.docker.internal"]
  // https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
	// host.docker.internal is set only in some docker desktop versions, and it
	// is inconsistent. Hence we set it to host-gateway always.
  extra_hosts: [ "host.docker.internal:host-gateway", "gateway.docker.internal:host-gateway" ]
	entrypoint: [ "/monorepo/plugins/devserver/inception.sh" ]
}

buildtime_inception: {
  network: "host"
	// inject secrets which holds the ip of the docker host and
	// host-gateway. We do it through secrets to avoid breaking cache.
  secrets: [ "docker_host_ip", "docker_gateway_ip" ]
}

nointernet: {
  // https://stackoverflow.com/a/61243361
  dns: "0.0.0.0"
}

services: {
	develop: runtime_inception & { command: string, build: build_debug }
	integrate: { command: "true", build: build_integrate }
}

secrets: {
	docker_host_ip: environment: "DOCKER_HOST_IP"
	docker_gateway_ip: environment: "DOCKER_GATEWAY_IP"
}
