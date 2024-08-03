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

# Print external command and execute it. Only for external commands.
def --wrapped vrun [cmd, ...args] {
  print $"($cmd) ($args | str join ' ')"
  ^$cmd ...$args
}

def vet [...args] { true }
def test [...args] { vtr test ...$args }
def build [...args] { vtr build ...$args }
def develop [...args] { vrun docker compose run --build develop ...$args }
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
    "setup" => { setup },
    "vet" => { vet },
    "build" => { build ...$args },
    "test" => { test ...$args },
    "develop" => { develop ...$args },
    "integrate" => { integrate ...$args },
    "preview" => { preview ...$args },
    _ => {
       $"subcommand ($subcommand) not found"
    }
  }
}
