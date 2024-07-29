package docker

import "encoding/json"
import "strings"

#run: {
	cmd?: string
	scripts: *[] | [...string]
	files: *[] | [...string]
	dirs: *[] | [...string]
	from: *[] | [ ...string ]
	stmt: *[] | [ ...string ]
}
#image: {
	from: *"scratch" | string
	as: string
	workdir: *"" | string
	env: *[] | [...string],
	mount: *[] | [...string],
	entrypoint: *[] | [ ...string ]
	cmd: *[] | [ ...string ]
	expose: *[] | [ ...int ] | [ ...string ]
	run: *[] | [ ...#run ]
}

#dockerfile: {
	stages: [...#image]
	contents: strings.Join([ for i in stages { (#stage & { image: i} ).contents } ], "\n\n")
}

#stage: {
	image: #image
	contents: string
	_cmds: [
		for r in image.run {
		strings.Join(
		r.stmt +
	[for f in (r).from { "COPY --from=\(f)  /monorepo /monorepo" } ] +
	[for d in (r).dirs { "COPY " + image.workdir + (d) + " " + (d) }] +
	[if (r).scripts != [] { "COPY --chmod=0755 " + strings.Join([for s in (r).scripts { "\(image.workdir)\(s)" }], " ") + " ./"  } ] +
	[if (r).files != [] { "COPY " + strings.Join([for f in (r).files { image.workdir + (f) }], " ") + " ./" } ] +
	[if (r).cmd != _|_ { "RUN " + strings.Join([ for m in image.mount { "--mount=\(m)" } ], " ") + " \((r).cmd)" }] +
	[], "\n"
	)
	}
	]
	contents: strings.Join(
	[ "FROM " + image.from + " AS " + image.as, "WORKDIR /monorepo/" + image.workdir ] +
	[ for p in image.expose { "EXPOSE \(p)" } ] +
	[ for e in image.env { "ENV \(e)" } ] +
		_cmds +
	[ if image.entrypoint != [] { "ENTRYPOINT [" + strings.Join([for e in image.entrypoint { "\"\(e)\"" }], ",") + "]" } ] +
	[ if image.cmd != [] { "CMD \(json.Marshal(image.cmd))" } ]
		"\n")
}

#gradle: #run & {
	scripts: [ "gradlew", "gradlew.bat"],
	files: ["gradle.properties", "settings.gradle.kts", "build.gradle.kts" ],
	dirs: [ "gradle" ]
}

#pnpm: #run & {
	files: [ "package.json" ]
}

#nuxt: #run & {
	files: [ "app.vue", "nuxt.config.ts" ],
	dirs: [ "assets", "components", "interfaces", "layouts", "middleware", "pages", "plugins", "public", "server", "utils" ]
}

