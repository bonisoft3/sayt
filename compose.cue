package compose

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
	context:    *"../.." | "."
	dockerfile: string
	target:     "debug"
}

runtime_inception: {
	volumes: caches + [
		"//var/run/docker.sock:/var/run/docker.sock",
		//"${HOME:-~}/.kube:/root/.kube",
		//"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
	]
	// we do not enable host network since it does not work consistently across
	// windows/mac/linux: https://stackoverflow.com/a/73683405/24313576
	// network_mode: "host"
	environment: ["TESTCONTAINERS_HOST_OVERRIDE=gateway.docker.internal"]
	// https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
	// host.docker.internal is set only in some docker desktop versions, and it
	// is inconsistent. Hence we set it to host-gateway always.
	extra_hosts: [ "host.docker.internal:host-gateway", "gateway.docker.internal:host-gateway" ]
	entrypoint: [ "/monorepo/plugins/devserver/inception.sh" ]
}

nointernet: {
  // https://stackoverflow.com/a/61243361
  dns: "0.0.0.0"
}

services: {
	develop: runtime_inception & { 
		command: string, 
		ports: *[] | [...string]
		build: build
	}
}
