package compose

volumes: {
  "root-dot-docker-cache-mount": {}
}

caches: [
  "${DIND:+/root/.dcm}${DIND:-root-dot-docker-cache-mount}:/root/.dcm"
]

buildctx: {
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
	// notice it does not work consistently across
	// windows/mac/linux: https://stackoverflow.com/a/73683405/24313576
	network_mode: "host"
	environment: ["TESTCONTAINERS_HOST_OVERRIDE=gateway.docker.internal"]
	// https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
	// host.docker.internal is set only in some docker desktop versions, and it
	// is inconsistent. Hence we set it to host-gateway always.
	extra_hosts: [ "host.docker.internal:host-gateway", "gateway.docker.internal:host-gateway" ]
	entrypoint: [ "/monorepo/plugins/devserver/inception.sh" ]
}

services: {
	develop: runtime_inception & { 
		command: string, 
		ports: *[] | [...string]
		build: buildctx
	}
}
