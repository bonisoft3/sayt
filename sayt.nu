#!/usr/bin/env nu
use std

def main [
   --directory (-d) = ".",  # directory where to run the command
   subcommand?: string, ...args] {
   if $subcommand == null { 
     help sayt 
   } else { 
     sayt --directory $directory $subcommand ...$args 
   }
}

def test [...args] { sh vtr test ...$args }
def build [...args] { sh vtr build ...$args }
def develop [...args] { docker compose run --build develop ...$args }
def integrate [...args] { docker compose run --build integrate ...$args }

def install [] {
  if ((sys | get host.name) == 'Windows') {
    pwsh -c .pkgx.ps1
  } else {
    bash -c "dev && vtr build || true"
  }
}

def sh [...command: string] {
  if ((sys | get host.name) == 'Windows') {
    pwsh.exe -c ...$command
  } else {
    bash -c ...$command
  }
}

def sayt [
   --directory (-d) = ".",  # directory where to run the command
   subcommand: string, ...args] {
  cd $directory
  match $subcommand {
    "install" => { install },
    "build" => { build ...$args },
    "test" => { test ...$args },
    "develop" => { develop ...$args },
    "integrate" => { integrate ...$args },
    _ => { help sayt }
  }
}
