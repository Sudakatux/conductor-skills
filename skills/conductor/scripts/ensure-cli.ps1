# Find a conductor CLI, or install the pinned release.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File ensure-cli.ps1
#       any conductor on PATH or in the install dir
#   ... -File ensure-cli.ps1 -Need create-app[,integration]
#       one that has these commands; exit 3 when missing or too old
#   ... -File ensure-cli.ps1 -Need create-app -Install
#       download, verify sha256, install
#
# Success prints: CONDUCTOR_BIN=C:\full\path\to\conductor.exe
# Install dir: $env:CONDUCTOR_CLI_DIR, else %LOCALAPPDATA%\Programs\conductor.
# No admin rights, no Node, no PATH or profile edits. Works on Windows PowerShell 5.1 and PowerShell 7.
param([string[]]$Need = @(), [switch]$Install)
$ErrorActionPreference = 'Stop'

# Pinned release; keep in step with ensure-cli.sh.
$CliRepo = 'Sudakatux/conductor-cli'   # FORK ONLY: conductor-oss/conductor-cli once `create-app` ships
$CliVersion = 'v0.1.10-createapp.2'
$Sha = @{
    'conductor_windows_amd64.exe' = '1f9d8e174c3b59b4a370097ebb0ec88e95f3eacfc315c0d0f777574d772610f7'
    'conductor_windows_arm64.exe' = '385ab01ac74516994fc13b3e29a6b631074b041185c3f0adcf002f933ad16918'
}

# -Need accepts "create-app,integration" as one string or as an array.
$Need = @($Need | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($n in $Need) {
    if ($n -notin @('create-app', 'integration')) {
        [Console]::Error.WriteLine("unknown -Need value: $n (create-app, integration)")
        exit 2
    }
}
$NeedCsv = $Need -join ','

$Dir = if ($env:CONDUCTOR_CLI_DIR) { $env:CONDUCTOR_CLI_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\conductor' }
$Target = Join-Path $Dir 'conductor.exe'

# Run a native command and return only its exit code. Output is discarded through
# cmd.exe so Windows PowerShell 5.1 never turns its stderr into a terminating error
# under $ErrorActionPreference = 'Stop'.
function Get-ExitCode([string]$Exe, [string]$CmdArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        cmd.exe /d /c "`"$Exe`" $CmdArgs >nul 2>&1"
        return $LASTEXITCODE
    } catch {
        return 1
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Test-Usable([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    foreach ($n in $Need) {
        $probe = if ($n -eq 'create-app') { 'create-app --help' } else { 'integration add --help' }
        if ((Get-ExitCode $Path $probe) -ne 0) { return $false }
    }
    return $true
}

# Only real executables: an npm `conductor.ps1` shim would be blocked by the execution policy.
$onPath = (Get-Command conductor -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (Test-Usable $onPath) { "CONDUCTOR_BIN=$onPath"; exit 0 }
if (Test-Usable $Target) { "CONDUCTOR_BIN=$Target"; exit 0 }

$needArg = if ($NeedCsv) { " -Need $NeedCsv" } else { '' }
if (-not $Install) {
    $existing = if ($onPath) { $onPath } elseif (Test-Path -LiteralPath $Target) { $Target } else { $null }
    if ($existing) { [Console]::Error.WriteLine("MISSING: $existing lacks one of: $NeedCsv (too old).") }
    else { [Console]::Error.WriteLine('MISSING: no conductor CLI found.') }
    [Console]::Error.WriteLine("Ask the user, then run: powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$needArg -Install  (installs $CliVersion to $Dir)")
    exit 3
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$asset = "conductor_windows_$arch.exe"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("conductor-" + [Guid]::NewGuid() + '.exe')
$url = "https://github.com/$CliRepo/releases/download/$CliVersion/$asset"
[Console]::Error.WriteLine("Downloading $url")
# Windows PowerShell 5.1 may default to TLS 1.0; GitHub needs TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
} catch {
    [Console]::Error.WriteLine("download failed: $url ($($_.Exception.Message))")
    exit 1
}

$got = (Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLower()
if ($got -ne $Sha[$asset]) {
    Remove-Item $tmp -Force
    [Console]::Error.WriteLine("CHECKSUM MISMATCH for ${asset}: expected $($Sha[$asset]), got $got. Not installed.")
    exit 1
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Move-Item -Force $tmp $Target
if (-not (Test-Usable $Target)) { [Console]::Error.WriteLine("installed $Target but it lacks one of: $NeedCsv"); exit 1 }
[Console]::Error.WriteLine("Installed conductor $CliVersion (sha256 verified).")
"CONDUCTOR_BIN=$Target"
