param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

if (-not (Get-Command nu -ErrorAction SilentlyContinue)) { 
   scoop install nushell
} 
$scriptDirectory = Split-Path -Path $PSCommandPath
nu $scriptDirectory\sayt.nu @Args
