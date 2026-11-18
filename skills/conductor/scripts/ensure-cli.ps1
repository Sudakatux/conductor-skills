# Find a conductor CLI that has `create-app` and `integration`, or install the pinned release.
#
#   powershell -File ensure-cli.ps1            # check only; exit 3 when missing
#   powershell -File ensure-cli.ps1 -Install   # download, verify sha256, install
#
# Success prints: CONDUCTOR_BIN=C:\full\path\to\conductor.exe
# Install dir: $env:CONDUCTOR_CLI_DIR, else %LOCALAPPDATA%\Programs\conductor.
# No admin rights, no Node, no PATH or profile edits.
param([switch]$Install)
$ErrorActionPreference = 'Stop'

# Pinned release; keep in step with ensure-cli.sh.
$CliRepo = 'Sudakatux/conductor-cli'   # FORK ONLY: conductor-oss/conductor-cli once `create-app` ships
$CliVersion = 'v0.1.10-createapp.1'
$Sha = @{
    'conductor_windows_amd64.exe' = '6c33da39d20328a49f0dd8af008d82c8a423e0b27b35d16eca79d0802416103b'
    'conductor_windows_arm64.exe' = 'ab473bb709b1685fc91986d89407bd1ab8bcd77f11237db95d7f32d1e2ba5c77'
}

$Dir = if ($env:CONDUCTOR_CLI_DIR) { $env:CONDUCTOR_CLI_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\conductor' }
$Target = Join-Path $Dir 'conductor.exe'

function Test-Login([string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) { return $false }
    & $Path create-app --help *> $null
    if ($LASTEXITCODE -ne 0) { return $false }
    & $Path integration add --help *> $null
    return $LASTEXITCODE -eq 0
}

$onPath = (Get-Command conductor -ErrorAction SilentlyContinue).Source
if (Test-Login $onPath) { "CONDUCTOR_BIN=$onPath"; exit 0 }
if (Test-Login $Target) { "CONDUCTOR_BIN=$Target"; exit 0 }

if (-not $Install) {
    if ($onPath) { [Console]::Error.WriteLine("MISSING: $onPath lacks 'create-app' or 'integration' (too old).") }
    else { [Console]::Error.WriteLine('MISSING: no conductor CLI found.') }
    [Console]::Error.WriteLine("Ask the user, then run: powershell -File `"$PSCommandPath`" -Install  (installs $CliVersion to $Dir)")
    exit 3
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$asset = "conductor_windows_$arch.exe"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("conductor-" + [Guid]::NewGuid() + '.exe')
$url = "https://github.com/$CliRepo/releases/download/$CliVersion/$asset"
[Console]::Error.WriteLine("Downloading $url")
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

$got = (Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLower()
if ($got -ne $Sha[$asset]) {
    Remove-Item $tmp -Force
    [Console]::Error.WriteLine("CHECKSUM MISMATCH for ${asset}: expected $($Sha[$asset]), got $got. Not installed.")
    exit 1
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Move-Item -Force $tmp $Target
if (-not (Test-Login $Target)) { [Console]::Error.WriteLine("installed $Target but it has no 'create-app'"); exit 1 }
[Console]::Error.WriteLine("Installed conductor $CliVersion (sha256 verified).")
"CONDUCTOR_BIN=$Target"
