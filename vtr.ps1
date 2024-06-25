param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)
Write-Output ("vtr " + $Args)
pipx run -q vscode-task-runner @Args
