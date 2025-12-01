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
		list.Concat([s.args, [ (#_makeArg & { image: s.sources, as: "\(s._prefix)_sources"}).arg ]])
	} ] }
	_flat: list.FlattenN(_args, 1)
	_unique: [
    for i, v in _flat if !list.Contains([for x in list.Slice(_flat, 0, i) { x.image.as } ], v.image.as) { v }
  ]
	args: _unique
}

// --- Refactored Helper: Only computes args from SOURCES ---
#_makeSourceArgs: {
	X1=stacks: [ ...#stack ]

	// 1. Generate only the args derived from s.sources
	_sourceArgs: [
		for s in X1 {
			(#_makeArg & { image: s.sources, as: "\(s._prefix)_sources"}).arg
		}
	]

	// 2. Apply uniqueness ONLY to these source args
	// Using the O(N^2) check based on v.image.as
	_flat: _sourceArgs // Already flat
	_unique: [
		for i, v in _flat
		// Ensure v.image.as exists before comparing
		if v.image.as != null && !list.Contains([
			// List comprehension to get 'as' strings from preceding slice
			for x in list.Slice(_flat, 0, i) if x.image.as != null { x.image.as }
		], v.image.as) {
			v
		}
	]
	// Return the unique source args
	uniqueSourceArgs: _unique
}


#basic: #stack & {
	X1=copy: [ ...#stack ]
	X2=dir: string
	X3=add: [ ...docker.#image ]

	// Calculate args locally, breaking the recursive call to the original #_makeArgs
	_args_step1: [ (#_makeArg & { image: devserver.#devserver }).arg ]
	_args_step2: [ for i in X3 { (#_makeArg & { image: i }).arg } ]
	// Get s.args directly - this dependency remains but is simpler
	_args_step3: list.FlattenN([ for s in X1 { s.args } ], 1)
	// Use the new helper for source args (doesn't depend on s.args)
	_args_step4: (#_makeSourceArgs & { stacks: X1 }).uniqueSourceArgs

	// Combine all parts
	_combinedArgs: list.Concat([ _args_step1, _args_step2, _args_step3, _args_step4 ])

	// Apply final uniqueness to the combined list
	_flat: _combinedArgs // Already flat
	_unique: [
		for i, v in _flat
		if v.image.as != null && !list.Contains([
			for x in list.Slice(_flat, 0, i) if x.image.as != null { x.image.as }
		], v.image.as) {
			v
		}
	]

	args: _unique // Final args for #basic


	// args: list.Concat([
	// 	[ (#_makeArg & { image: devserver.#devserver }).arg ],
	// 	[ for i in X3 { (#_makeArg & { image: i }).arg } ],
	// 	(#_makeArgs & { stacks: X1 }).args])
	sources: docker.#image & {
		from: devserver.#devserver.from
		as: *"sources" | string
		workdir: X2
		run: [ { from: list.Concat([[ for i in X3 { i.as } ], [ for s in X1 if s._prefix != _|_ { "\(s._prefix)_sources" } ]]), dirs: [ "." ] } ]
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
		setup: [ docker.#run & { cmd: "[ ! -e .mise.toml ] || just setup" } ]
		build: [ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just build" } ]
		test: [ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just test" } ]
		launch: [ docker.#run & { cmd: "[ ! -e .vscode/launch.json ] || just launch" } ]
	}
	sources: docker.#image & {
		from: devserver.#devserver.from
		as: *"sources" | string
		run: list.Concat([layers.sayt, layers.deps, layers.dev, layers.test, layers.ops])
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
	#mise: {
		_jdk: "openjdk"
		_jdk_version: "21.0"
		dependencies: """
		[tools]
		java = "\(_jdk)@\(_jdk_version)"
		"""
	}
	#config: docker.#run & {
		scripts: ["gradlew"]
		files: ["gradlew.bat", "gradle.properties", "settings.gradle*", "build.gradle*"]
		dirs: ["gradle"]
	}


		// Calculate args locally using the refactored approach
	_args_step1: [
		(#_makeArg & {image: devserver.#devserver }).arg,
		(#_makeArg & {image: root.#sayt, as: "root_sayt" }).arg,
		(#_makeArg & {image: root.#gradle, as: "root_gradle" }).arg,
	]
	_args_step2: list.FlattenN([ for s in X1 { s.args } ], 1) // Get s.args directly
	_args_step3: (#_makeSourceArgs & { stacks: X1 }).uniqueSourceArgs // Use helper

	_combinedArgs: list.Concat([ _args_step1, _args_step2, _args_step3 ])

	// Apply final uniqueness
	_flat: _combinedArgs
	_unique: [
		for i, v in _flat
		if v.image.as != null && !list.Contains([
			for x in list.Slice(_flat, 0, i) if x.image.as != null { x.image.as }
		], v.image.as) {
			v
		}
	]
	args: _unique // Final args for #gradle

	layers: {
		sayt: *([ { files: [ ".mise.toml", ".mise.lock", ".mise.alpine.lock" ], from: list.Concat([[ "root_sayt", "root_gradle" ], [ for s in copy { "\(s._prefix)_sources" } ]]) } ]) | [ ...docker.#run ]
		deps: *[ #config ] | [ ...docker.#run ]
		dev: *[ docker.#run & { dirs: ["src/main", ".vscode"] }] | [ ...docker.#run ]
		test: *[ docker.#run & { dirs: ["src/test"] }] | [ ...docker.#run ]
		ops: *[ docker.#run & { files: [ "Dockerfile", "compose.yaml", "skaffold.yaml"], dirs: [ "src/it" ] } ] | [ ...docker.#run ]
	}
	sources:
		workdir: X2
	debug: {
		workdir: X2
		// https://forums.docker.com/t/understanding-how-host-file-blocking-interferes-with-docker-communication-127-0-0-1-issue/145481/25.
		env: [ "GRADLE_USER_HOME='/root/.dcm/gradle'" , "JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true" ]
		mount: list.Concat([devserver.#devserver.mount, [ "type=cache,sharing=locked,target=/root/.dcm/gradle" ]])
		run: list.Concat([
			L.sayt, C.setup, L.deps,
			[ docker.#run & { cmd: "./gradlew dependencies" } ],
			L.dev,  C.build, L.test])
	}
	integrate: {
		mount: list.Concat([devserver.#devserver.mount, [ "type=cache,sharing=locked,target=/root/.dcm/gradle" ]])
		workdir: X2
	}
}
#pnpm: #advanced & {
	X1=copy: [ ...#stack ]
	X2=dir: string
	let L=layers
	let C=#advanced.#commands
	#mise: {
		_nodejs: "nodejs"
		_nodejs_version: "22.14.0"
		_pnpm: "pnpm"
		_pnpm_version: "9.15.2"
		dependencies: """
		[tools]
		nodejs = "\(_nodejs)@\(_nodejs_version)"
		pnpm = "\(_pnpm)@\(_pnpm_version)"
		"""
	}
	#nuxt: docker.#run & {
		files: ["app.vue", "nuxt.config.ts", "tsconfig.json", "app.config.ts", ".nuxtignore", ".env", ".npmrc" ]
		dirs: ["assets", "components", "composables","content", "layouts", "middleware", "modules", "pages", "plugins", "public", "server", "utils", "types"]
		stmt: [ "# https://code.visualstudio.com/docs/containers/debug-node#_mapping-docker-container-source-files-to-the-local-workspace" ],
		cmd: "mkdir /usr/src && ln -s . /usr/src/app"
	}
	#next: docker.#run & {
		files: ["next.config.mjs", "next-env.d.ts", "tsconfig.json", ".env", "package.json"]
		dirs: ["app", "components", "styles", "public"]
		stmt: [ "# https://code.visualstudio.com/docs/containers/debug-node#_mapping-docker-container-source-files-to-the-local-workspace" ]
		cmd: "mkdir /usr/src && ln -s . /usr/src/app"
	}
	#vitest: docker.#run & {
		files: [ "vitest.*" ]
		dirs: [ "tests" ]
	}
	args: list.Concat([[
		(#_makeArg & {image: devserver.#devserver }).arg,
		(#_makeArg & {image: root.#sayt, as: "root_sayt" }).arg,
		(#_makeArg & {image: root.#pnpm, as: "root_pnpm" }).arg,
	], (#_makeArgs & { stacks: X1 }).args])
	layers: {
				sayt: *([ { files: [ ".mise.toml", ".mise.lock", ".mise.alpine.lock" ], from: list.Concat([[ "root_sayt", "root_pnpm" ], [ for s in copy { "\(s._prefix)_sources" } ]]) } ]) | [ ...docker.#run ]
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
		run: list.Concat([
			L.sayt, C.setup,
			[ { cmd: "pnpm --dir /monorepo/ install --frozen-lockfile" } ],
			L.deps,
			[ { cmd: "pnpm install --frozen-lockfile", files: [ "package.json" ] } ],
			L.dev,
	  	[ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just build" } ], L.test,
			[ docker.#run & { cmd: "[ ! -e .vscode/tasks.json ] || just test" } ],
			L.ops])
	}
	integrate: {
		workdir: X2
		mount: devserver.#devserver.mount
		run: *(list.Concat([[ { cmd: "pnpm build test:int --run" } ], C.launch])) | [ ...docker.#run ]
	}
}
