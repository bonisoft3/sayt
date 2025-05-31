package docker

import "encoding/json"
import "strings"
import "list"

#run: {
	cmd?: string
	scripts?: [...string]
	files?: [...string]
	dirs?: [...string]
	from?: [ ...string ]
	stmt?: [ ...string ]
}

#image: {
	as: string
  from: *"scratch" | string
	workdir: string
	env?: [...string],
	mount?: [...string],
	entrypoint?: [ ...string ]
	cmd?: [ ...string ]
	expose?: [ ...int ] | [ ...string ]
	run?: [ ...#run ]
}

#arg: {
  name: string
	default: string
  image?: #image
}

#dockerfile: {
	X1=args: [ ...#arg ]
	X2=images: [ ...#image ]
	contents: string
	_unique: (#_uniqueArgs & { args: X1 }).unique
	_args: strings.Join([ for a in _unique { "ARG \(a.name)=\(a.default)" } ], "\n")
	_args_images: [ for a in _unique if (a.image != _|_) { a.image } ]
	_stages: [ ...string ]
	_stages: [ for i in list.Concat([_args_images, X2]) { (#printStageFn & { stage: i} ).out } ]
	contents: strings.Join(list.Concat([[_args],_stages]), "\n\n")
}

#_uniqueArgs: {
  X1=args: [...#arg]
  unique: [...#arg]
  unique: [
    for i, v in X1 if !list.Contains(list.Slice(X1, 0, i), v) { v }
  ]
}

#printRunFn: {
	image: #image
	run: #run
	out: string
	out: strings.Join(list.Concat([
		[ if run.stmt != _|_ for s in run.stmt { s } ],
		[ if run.from != _|_ for f in (run.from) if f != _|_ { "COPY --from=\(f) /monorepo /monorepo" } ],
		[ if run.dirs != _|_ for d in (run.dirs) { "COPY " + image.workdir + (d) + " " + strings.Replace(strings.Replace(d, "[", "", -1), "]", "", -1) } ],
		[ if run.scripts != _|_ { "COPY --chmod=0755 " + strings.Join([for s in run.scripts { "\(image.workdir)\(s)" }], " ") + " ./"  } ],
		[ if run.files != _|_ { "COPY " + strings.Join([for f in run.files { image.workdir + (f) }], " ") + " ./" } ],
		[ if run.cmd != _|_ { "RUN " + strings.Join([ if image.mount != _|_ for m in image.mount { "--mount=\(m)" } ], " ") + " \((run.cmd))" }],
		[ ]]), "\n"
	)
}

#printStageFn: {
	X1=stage: #image
	out: string
	_from: [ "FROM \(X1.from) AS \(X1.as)" ]
	_workdir: [ "WORKDIR /monorepo/\(X1.workdir)" ]
	_expose: [ if X1.expose != _|_ for p in X1.expose { "EXPOSE \(p)" } ]
	_env: [ if X1.env != _|_ for e in X1.env { "ENV \(e)" } ]
	_run: [ if X1.run != _|_ for r in X1.run { (#printRunFn & { image: X1, run: r}).out } ]
	_entrypoint: [ if X1.entrypoint != _|_ { "ENTRYPOINT [" + strings.Join([for e in X1.entrypoint { "\"\(e)\"" }], ",") + "]" } ]
	_cmd: [ if X1.cmd != _|_ { "CMD \(json.Marshal(X1.cmd))" } ]
	_lines: [ ...string ]
	_lines: list.Concat([_from, _workdir, _expose, _env, _run, _entrypoint, _cmd])
  out: strings.Join(_lines, "\n")
}
