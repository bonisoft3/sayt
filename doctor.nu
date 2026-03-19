# doctor.nu — Environment diagnostics
export def main [...args] {
	let envs = [ {
		"pkg": (check-installed mise scoop),
		"cli": (check-all-of-installed cue gomplate),
		"ide": (check-installed cue),
		"cnt": (check-installed docker),
		"k8s": (check-all-of-installed kind skaffold),
		"cld": (check-installed gcloud),
		"xpl": (check-installed crossplane)
	} ]
	print "Tooling Checks:"
	print ($envs | update cells { |val| convert-bool-to-checkmark $val } | first | transpose key value)

	# Release tool checks (context-dependent)
	let release_checks = (
		[
			(if ((".goreleaser.yaml" | path exists) or (".goreleaser.yml" | path exists)) { {key: "goreleaser", value: (check-installed goreleaser)} })
		] | compact
	)
	if ($release_checks | is-not-empty) {
		print ""
		print "Release Checks:"
		print ($release_checks | update value { |row| convert-bool-to-checkmark $row.value })
	}

	print ""
	print "Health Checks:"
	let dns = {
		"dns-google": (check-dns "google.com"),
		"dns-github": (check-dns "github.com")
	}
	print ($dns
	| transpose key value
	| update value { |row| convert-bool-to-checkmark $row.value })

	if ($dns | values | any { |v| $v == false }) {
		error make { msg: "DNS resolution failed. Network connectivity issues detected." }
	}
}

def convert-bool-to-checkmark [ val: bool ] {
  if $val { "✓" } else { "✗" }
}

def check-dns [domain: string] {
  try {
    (http head $"https://($domain)" | is-not-empty)
  } catch {
    false
  }
}

def check-all-of-installed [ ...binaries ] {
  $binaries | par-each { |val| check-installed $val } | all { |el| $el == true }
}

def check-installed [ binary: string, windows_binary: string = ""] {
	if ($nu.os-info.name == 'Windows') {
		if ($windows_binary | is-not-empty) {
			(which $windows_binary) | is-not-empty
		} else {
			(which $binary) | is-not-empty
		}
	} else {
		(which $binary) | is-not-empty
	}
}
