package stacks

import "bonisoft.org/plugins/sayt:docker"
import "bonisoft.org/plugins/devserver"
import "bonisoft.org:root"
import "list"
import "strings"

#stack: {
	dir: string
	args: [ ...docker.#arg ]
	sources: docker.#image
	_prefix: strings.Replace(strings.Replace(strings.TrimSuffix(dir, "/"), "/", "_", -1), "-", "_", -1)
	...
}

#_makeArg: {
	X1=image: docker.#image
	X2=as: *X1.as | string
	arg: docker.#arg & {
		name: strings.ToUpper(X2)
		default: X2
		image: (X1 & { as: X2 })
	}
}

#_makeArgs: {
	X1=stacks: [ ...#stack ]
	_args: [ ...[...docker.#arg] ] & { [ for s in X1 {
		s.args + [ (#_makeArg & { image: s.sources, as: "\(s._prefix)_sources"}).arg ]
	} ] }
	_flat: list.FlattenN(_args, 1)
	_unique: [ for i, v in _flat if !list.Contains(list.Slice(_flat, 0, i), v) { v } ]
	args: _unique
}

#basic: #stack & {
	X1=copy: [ ...#stack ]
	X2=dir: string
	X3=add: [ ...docker.#image ]
	args:
		[ (#_makeArg & { image: devserver.#devserver }).arg ] +
		[ for i in X3 { (#_makeArg & { image: i }).arg } ] +
		(#_makeArgs & { stacks: X1 }).args
	sources: docker.#image & {
		from: devserver.#devserver.from
		as: *"sources" | string
		workdir: X2
		run: [ { from: [ for i in X3 { i.as } ] + [ for s in X1 { "\(s._prefix)_sources" } ], dirs: [ "." ] } ]
	}
}

#advanced: #stack & {
	copy: [ ...#stack ]
	dir: string
	args: [ ...docker.#arg ]
	layers: {
		sayt: [ ...docker.#run ]
		deps: [ ...docker.#run ]
		dev: [ ...docker.#run ]
		test: [ ...docker.#run ]
		ops: [ ...docker.#run ]
	}
	#commands: {
		setup: [ docker.#run & { cmd: "[ ! -e .pkgx.yaml ] || just setup" } ]
		build: [ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just build" } ]
		test: [ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just test" } ]
		launch: [ docker.#run & { cmd: "[ ! -e .vscode/launch.json ] || just launch" } ]
	}
	sources: docker.#image & {
		from: devserver.#devserver.from
		as: *"sources" | string
		run: layers.sayt + layers.deps + layers.dev + layers.test + layers.ops
	}
	debug: docker.#image & {
		from: devserver.#devserver.as
		as: "debug"
		cmd: *["just", "launch"] | [ ...string ]
		run: [ ...docker.#run ]
	}
	integrate: docker.#image & {
		from: debug.as
		as: "integrate"
		cmd: [ "true" ]
		run: [ ...docker.#run ]
	}
	#stages: [ sources , debug, integrate ]
}

#gradle: #advanced & {
	X1=copy: [ ...#stack ]
	X2=dir: string
	let L=layers
	let C=#advanced.#commands
	#pkgx: {
		_jdk: "openjdk"
		_jdk_version: "21.0"
		dependencies: _jdk + ".org@" + _jdk_version
		env: [ { "SAY_SCOOP_BUCKET_ADD": "java" }, { "SAY_SCOOP_INSTALL": _jdk + "@" + _jdk_version } ]
	}
	#config: docker.#run & {
		scripts: ["gradlew"]
		files: ["gradlew.bat", "gradle.properties", "settings.gradle*", "build.gradle*"]
		dirs: ["gradle"]
	}
	args: [
		(#_makeArg & {image: devserver.#devserver }).arg,
		(#_makeArg & {image: root.#sayt, as: "root_sayt" }).arg,
		(#_makeArg & {image: root.#gradle, as: "root_gradle" }).arg
	] + (#_makeArgs & { stacks: X1 }).args
	layers: {
		sayt: *([ { files: [ ".pkgx.yaml" ], from: [ "root_sayt", "root_gradle" ] + [ for s in copy { "\(s._prefix)_sources" } ] } ]) | [ ...docker.#run ]
		deps: *[ #config ] | [ ...docker.#run ]
		dev: *[ docker.#run & { dirs: ["src/main", ".vscode"] }] | [ ...docker.#run ]
		test: *[ docker.#run & { dirs: ["src/test"] }] | [ ...docker.#run ]
		ops: *[ docker.#run & { files: [ "Dockerfile", "compose.yaml", "skaffold.yaml"], dirs: [ "src/it" ] } ] | [ ...docker.#run ]
	}
	sources:
		workdir: X2
	debug: {
		workdir: X2
		env: [ "GRADLE_USER_HOME='/root/.dcm/gradle'"]
		mount: devserver.#devserver.mount + [ "type=cache,sharing=locked,target=/root/.dcm/gradle" ]
		run:
			L.sayt + C.setup + L.deps +
			[ docker.#run & { cmd: "./gradlew dependencies" } ] +
			L.dev +  C.build + L.test
	}
	integrate: {
		mount: devserver.#devserver.mount + [ "type=cache,sharing=locked,target=/root/.dcm/gradle" ]
		workdir: X2
	}
}
#pnpm: #advanced & {
	X1=copy: [ ...docker.#image ]
	X2=dir: string
	let L=layers
	let C=#advanced.#commands
	#pkgx: {
		_nodejs: "nodejs"
		_nodejs_version: "22.10"
		_pnpm: "pnpm"
		_pnpm_version: "9.12.2"
		dependencies: "\(_nodejs).org@\(_nodejs_version) \(_pnpm).io@\(_pnpm_version)"
		env: [ { "SAY_SCOOP_INSTALL": "\(_nodejs)@\(_nodejs_version) \(_pnpm)@\(_pnpm_version) _jdk" } ]
	}
	#nuxt: docker.#run & {
		files: ["app.vue", "nuxt.config.ts", "tsconfig.json", "app.config.ts", ".nuxtignore", ".env", ".npmrc" ]
		dirs: ["assets", "components", "composables","content", "layouts", "middleware", "modules", "pages", "plugins", "public", "server", "utils"]
		stmt: [ "# https://code.visualstudio.com/docs/containers/debug-node#_mapping-docker-container-source-files-to-the-local-workspace" ],
		cmd: "mkdir /usr/src && ln -s . /usr/src/app"
	}
	#vitest: docker.#run & {
		files: [ "vitest.*" ]
		dirs: [ "tests" ]
	}
	args: [
		(#_makeArg & {image: devserver.#devserver }).arg,
		(#_makeArg & {image: root.#sayt, as: "root_sayt" }).arg,
		(#_makeArg & {image: root.#pnpm, as: "root_pnpm" }).arg,
	] + (#_makeArgs & { stacks: X1 }).args
	layers: {
		sayt: *([ { files: [ ".pkgx.yaml" ], from: [ "root_sayt", "root_pnpm" ] + [ for s in copy { "\(s._prefix)_sources" } ] }]) | [ ...docker.#run ]
		deps: *[ { files: [ "package.json" ] } ] | [ ...docker.#run ]
		dev: *[ { dirs: [ ".vscode" ] }, #nuxt ] | [ ...docker.#run ]
		test: *[ #vitest ] | [ ...docker.#run ]
		ops: *[ docker.#run & { files: [ "Dockerfile", "Dockerfile.cue", "skaffold.yaml", "compose-cache.json" ] } ] | [ ...docker.#run ]
	}
	sources:
		workdir: X2
	debug: {
		workdir: X2
		mount: devserver.#devserver.mount
		run:
			L.sayt + C.setup +
			[ { cmd: "cd /monorepo && pkgx +nodejs.org@\(#pkgx._nodejs_version) pnpm install --frozen-lockfile" } ] +
			L.deps +
			[ { cmd: "pkgx +nodejs.org@\(#pkgx._nodejs_version) pnpm install --frozen-lockfile", files: [ "package.json" ] } ] +
			L.dev + C.build + L.test + C.test + L.ops
	}
	integrate: {
		workdir: X2
		mount: devserver.#devserver.mount
		run: *([ { cmd: "pnpm build test:int --run" } ] + C.launch) | [ ...docker.#run ]
	}
}
