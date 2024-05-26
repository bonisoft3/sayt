param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)
$scriptDirectory = Split-Path -Path $PSCommandPath
nu $scriptDirectory\sayt.nu @Args
