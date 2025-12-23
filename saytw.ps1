$ErrorActionPreference = "Stop"
$Version = if ($env:SAYT_VERSION) { $env:SAYT_VERSION } else { "0.0.37" }
$CacheDir = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "sayt"
} elseif ($env:XDG_CACHE_HOME) {
    Join-Path $env:XDG_CACHE_HOME "sayt"
} else {
    Join-Path $env:HOME ".cache/sayt"
}
$Binary = Join-Path $CacheDir "sayt.com"
$ApeLoader = Join-Path $CacheDir "ape.elf"

if (-not (Test-Path $Binary)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    Write-Host "Downloading sayt.com v$Version..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://github.com/igorgatis/sayt/releases/download/$Version/sayt.com" -OutFile $Binary -UseBasicParsing
}

# On Linux, APE binaries need the APE loader to run from PowerShell
if ($IsLinux -and -not (Test-Path $ApeLoader)) {
    $arch = uname -m
    $apeUrl = if ($arch -eq "x86_64") { "https://justine.lol/ape.elf" } else { "https://justine.lol/ape.aarch64" }
    Write-Host "Downloading APE loader for $arch..."
    Invoke-WebRequest -Uri $apeUrl -OutFile $ApeLoader -UseBasicParsing
    chmod +x $ApeLoader
}

if ($IsLinux) {
    & $ApeLoader $Binary @args
} else {
    & $Binary @args
}
exit $LASTEXITCODE
