package say

say: lint: shared: [
	{pattern: "v\\d+\\.\\d+\\.\\d+", files: ["VERSION", "saytw", "saytw.ps1", "compose.yaml", "config.cue"]},
	{pattern: "\\d+\\.\\d+\\.\\d+", files: ["VERSION", ".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"]},
	{pattern: "moby/buildkit:v0\\.30\\.0@sha256:0168606be2315b7c807a03b3d8aa79beefdb31c98740cebdffdfeebf31190c9f", files: [
		".github/actions/sayt/integrate/action.yml",
		".github/workflows/cd.yml",
	]},
]
