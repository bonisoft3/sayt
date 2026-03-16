package say

say: lint: rulemap: "version-sync": {
	cmds: [{do: "lint-version", use: "./lint-version.nu"}]
}
