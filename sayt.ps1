$ErrorActionPreference = "Stop"

$RootDir = $PSScriptRoot
$CacheDir = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "sayt"
} elseif ($env:XDG_CACHE_HOME) {
    Join-Path $env:XDG_CACHE_HOME "sayt"
} else {
    Join-Path $env:HOME ".cache/sayt"
}
$ShimsDir = if ($env:MISE_DATA_DIR) {
    Join-Path $env:MISE_DATA_DIR "shims"
} elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "mise\shims"
} else {
    Join-Path $env:HOME ".local/share/mise/shims"
}

$MiseVersion = (Select-String -Path (Join-Path $RootDir "sayt.sh") -Pattern '^MISE_VERSION="([^"]+)"').Matches[0].Groups[1].Value
$MiseDir = Join-Path $CacheDir "mise-$MiseVersion"
$MiseBin = Join-Path $MiseDir "mise.exe"

if (-not (Test-Path $MiseBin)) {
    $ArchName = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        default { Write-Error "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE"; exit 1 }
    }
    $MiseUrl = if ($env:SAYT_MISE_URL) {
        $env:SAYT_MISE_URL
    } else {
        $Base = if ($env:SAYT_MISE_BASE) { $env:SAYT_MISE_BASE.TrimEnd('/') } else { "https://github.com/jdx/mise/releases/download/$MiseVersion" }
        "$Base/mise-$MiseVersion-windows-$ArchName.exe"
    }
    New-Item -ItemType Directory -Path $MiseDir -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $TmpBin = "$MiseBin.part.$PID"
    try {
        Invoke-WebRequest -Uri $MiseUrl -OutFile $TmpBin -UseBasicParsing
    } catch {
        Remove-Item -Path $TmpBin -Force -ErrorAction SilentlyContinue
        throw
    }
    Move-Item -Path $TmpBin -Destination $MiseBin -Force
}

$NuStub = Join-Path $RootDir "nu.toml"
if (Test-Path (Join-Path $RootDir ".mise.toml")) {
    & $MiseBin trust -y -a -q
}

$env:SAYT_MISE_BIN = $MiseBin
$env:MISE_LOCKED = "0"
$env:PATH = "$MiseDir;$ShimsDir;$env:PATH"
& $MiseBin tool-stub $NuStub (Join-Path $RootDir "sayt.nu") @args
exit $LASTEXITCODE
