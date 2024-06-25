package plugins_sayt

build: {
	context:    "../.."
	dockerfile: string
	target:     string
	cache_from: ["type=gha,mode=max"]
	cache_to: ["type=gha,mode=max"]
}

debug: build & {
  target: "debug"
}

prebuilt: build & {
  target: "prebuilt"
}

release: build &  {
  target: "release"
}

inception: {
  volumes: [
	"//var/run/docker.sock:/var/run/docker.sock",
	"${HOME:-~}/.kube:/root/.kube",
	"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
  ]
  network_mode: "host"
  environment: ["TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal"]
}

nointernet: {
  // https://stackoverflow.com/a/61243361
  dns: "0.0.0.0"
  // https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
  extra_hosts: [ "host.docker.internal:host-gateway" ]
}


services: {
  checkout: {
    command: "bash"
    build: debug
  }
  build: build: debug
  test: {
    network_mode: "none"
    command: *"just sayt test" | string
    build: prebuilt
  }
  develop: inception & {
    dns: "0.0.0.0"
    command: "vtr docker-run"
    build: prebuilt
  }
  integrate: inception & nointernet & {
    dns: "0.0.0.0"
    command: string
    build: prebuilt
  }
  preview: inception & {
    image: "${IMAGE:-release}"
    build: release
  }
}
