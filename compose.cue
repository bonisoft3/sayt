package compose

import "list"

volumes: {
  "root-dot-docker-cache-mount": {}
}

caches: [
  // "${DIND:+/root/.dcm}${DIND:-root-dot-docker-cache-mount}:/root/.dcm"
]

inception: {
	secrets: [ "host.env" ]
}
  

buildtime: inception & {
	network: "host"
	context:    *"../.." | "."
	dockerfile: string
	target:     *"debug" | "integrate"
}

runtime: inception & {
	volumes: list.Concat([caches, [
		"//var/run/docker.sock:/var/run/docker.sock",
		"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
	]])
	entrypoint: [ "/monorepo/plugins/devserver/dind.sh" ]
	secrets: [ "host.env" ]
	network_mode: "host"
}

services: {
	develop: runtime & { 
		command: string, 
		ports: *[] | [...string]
		build: buildtime
	}
	integrate: { 
		command: "true", 
		build: buildtime & {
			target: "integrate"
		}
	}
}

secrets: {
  "host.env": {
    environment: "HOST_ENV"
	}
}
