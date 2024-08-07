#!/usr/bin/env nu
use std log

def --wrapped main [
   --directory (-d) = ".",  # directory where to run the command
   subcommand?: string, ...args] {
   if $subcommand == null {
     help sayt
   } else {
     sayt --directory $directory $subcommand ...$args
   }
}

def setup [...args] {
  if ((sys host | get name) == 'Windows') {
    if (which scoop | is-empty) {
      vrun pwsh.exe -c $"($env.FILE_PWD)/../../bootstrap.ps1"
    }
    if ('.pkgx.ps1' | path exists) { pwsh.exe -c .pkgx.ps1 }
  } else {
    if (which pkgx | is-empty) {
      vrun sh $"($env.FILE_PWD)/../../bootstrap"
    }
    open -r .pkgx.yaml | from yaml | get dependencies | par-each { |it| vrun pkgx install $it }
    if ('.pkgx.sh' | path exists) {
      sh ./.pkgx.sh
    }
  }
}

def chat [...args] {
	if ($env.GROQ_API_KEY | is-empty) and ($args | is-empty) {
		log warning "GROQ_API_KEY is empty and no arguments provided"
		exit 1
	} else if ($args | is-empty) {
		aider --model groq/llama-3.1-70b-versatile
	} else {
		aider ...$args
	}
}

def convert-bool-to-checkmark [ it: bool ] {
  if $it { "✓" } else { "✗" }
}

def check-all-of-installed [ ...binaries ] {
  $binaries | par-each { |it| check-installed $it } | all { |el| $el == true }
}
def check-installed [ binary: string, windows_binary: string = ""] {
	if ((sys host | get name) == 'Windows') {
		if (windows_binary | is-not-empty) {
			(where $windows_binary) | is-not-empty
		} else {
			(where $binary) | is-not-empty
		}
	} else {
		(which $binary) | is-not-empty
	}
}

def doctor [...args] {
	let envs = [ {
		"pkg": (check-installed pkgx scoop),
		"cli": (check-all-of-installed cue aider),
		"ide": (check-installed vtr),
		"cnt": (check-installed docker),
		"k8s": (check-all-of-installed kind skaffold),
		"cld": (check-installed gcloud),
		"xpl": (check-installed crossplane)
	} ]
	$envs | update cells { |it| convert-bool-to-checkmark $it }
}

# Print external command and execute it. Only for external commands.
def --wrapped vrun [cmd, ...args] {
  print $"($cmd) ($args | str join ' ')"
  ^$cmd ...$args
}

def vet [...args] { true }
def test [...args] { vtr test ...$args }
def build [...args] { vtr build ...$args }
def develop [...args] { vrun docker compose up --build develop ...$args }
def integrate [...args] {
	if ((sys host | get name) == 'Darwin') {
		if not (^find $"($env.FILE_PWD)/../.." -xattr | is-empty) {
			log warning "Found extended attributes (xattr) which breaks nested docker cache"
		}
	}
  vrun docker compose run --build develop docker compose build integrate ...$args
}
def preview [...args] { vrun skaffold dev -p preview }

def vtr [...args: string] {
  if ((sys host | get name) == 'Windows') {
    vrun pwsh.exe -c $"($env.FILE_PWD)/vtr.ps1" ...$args
  } else {
    vrun sh $"($env.FILE_PWD)/vtr.sh" ...$args
  }
}

def --wrapped aider [...args: string] {
  if ((sys host | get name) == 'Windows') {
    vrun pwsh.exe -c $"($env.FILE_PWD)/aider.ps1" ...$args
  } else {
    vrun sh $"($env.FILE_PWD)/aider.sh" ...$args
  }
}


def sh [...command: string] {
  if ((sys host | get name) == 'Windows') {
    pwsh.exe -c ...$command
  } else {
    bash -c 'exec "$@"' -- ...$command
  }
}

def sayt [
   --directory (-d) = ".",  # directory where to run the command
   subcommand: string, ...args] {
  cd $directory
  match $subcommand {
    "setup" => { setup ...$args },
    "doctor" => { doctor ...$args },
    "chat" => { chat ...$args },
    "vet" => { vet ...$args },
    "build" => { build ...$args },
    "test" => { test ...$args },
    "develop" => { develop ...$args },
    "integrate" => { integrate ...$args },
    "preview" => { preview ...$args },
    "verify" => { verify ...$args },
    "stage" => { stage ...$args },
    "loadtest" => { loadtest ...$args },
    "publish" => { publish ...$args },
    "observe" => { observe ...$args },
    _ => {
       $"subcommand ($subcommand) not found"
    }
  }
}
