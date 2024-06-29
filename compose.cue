package plugins_sayt

volumes: {
  "root-dot-task": {}, 
  "root-dot-cache": {},
  "root-dot-pkgx": {},
  "root-dot-gradle": {},
  "root-dot-pnpm-store": {}
}

caches: [
  "root-dot-task:/root/.task",
  "root-dot-cache:/root/.cache",
  "root-dot-pkgx:/root/.pkgx",
  "root-dot-gradle:/root/.gradle",
  "root-dot-pnpm-store:/root/.local/share/pnpm/store"
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
	"${HOME:-~}/.kube:/root/.kube",
	"${HOME:-~}/.skaffold/cache:/root/.skaffold/cache",
  ]
  network_mode: "host"
  environment: ["TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal"]
  // https://forums.docker.com/t/map-service-in-docker-compose-to-host-docker-internal/119491
  extra_hosts: [ "host.docker.internal:host-gateway" ]
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
  build: inception & {
    build: debug
  }
  test: inception & {
    dns: "0.0.0.0"
    command: *"docker compose run --build --rm --entrypoint just build sayt test && just sayt test" | string
    build: debug
  }
  develop: inception & {
    dns: "0.0.0.0"
    command: "docker compose run --build --rm build && vtr docker-run"
    build: debug
  }
  integrate: inception & nointernet & {
    command: string
    build: debug
  }
  preview: inception & {
    image: "${IMAGE:-release}"
    build: release
  }
}
