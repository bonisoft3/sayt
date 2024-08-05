param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)
Write-Output ("aider " + $Args)
pipx run -q aider-chat @Args
