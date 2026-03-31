package say

say: lint: shared: [
	{pattern: "v\\d+\\.\\d+\\.\\d+", files: ["VERSION", "saytw", "saytw.ps1", "compose.yaml", "config.cue"]},
	{pattern: "\\d+\\.\\d+\\.\\d+", files: ["VERSION", ".claude-plugin/plugin.json", ".claude-plugin/marketplace.json"]},
]
