# Find a conductor CLI that has `create-app` and `integration`, or install the pinned release.
#
#   powershell -File ensure-cli.ps1            # check only; exit 3 when missing
#   powershell -File ensure-cli.ps1 -Install   # download, verify sha256, install
#   powershell -File ensure-cli.ps1 -AddToPath # also put the install dir on the user PATH
#
# Success prints: CONDUCTOR_BIN=C:\full\path\to\conductor.exe
# Install dir: $env:CONDUCTOR_CLI_DIR, else %LOCALAPPDATA%\Programs\conductor.
# No admin rights, no Node, no profile edits. The user PATH (HKCU\Environment)
# changes only with -AddToPath, after the user says yes; never added twice.
param([switch]$Install, [switch]$AddToPath)
$ErrorActionPreference = 'Stop'

# Pinned release; keep in step with ensure-cli.sh.
$CliRepo = 'Sudakatux/conductor-cli'   # FORK ONLY: conductor-oss/conductor-cli once `create-app` ships
$CliVersion = 'v0.1.10-createapp.2'
$Sha = @{
    'conductor_windows_amd64.exe' = '1f9d8e174c3b59b4a370097ebb0ec88e95f3eacfc315c0d0f777574d772610f7'
    'conductor_windows_arm64.exe' = '385ab01ac74516994fc13b3e29a6b631074b041185c3f0adcf002f933ad16918'
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

function Get-UserPath {
    # Raw value, so %USERPROFILE%-style entries stay unexpanded when we write it back.
    (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Test-InUserPath {
    $want = $Dir.TrimEnd('\')
    foreach ($p in ((Get-UserPath) -split ';')) {
        if ($p -and [Environment]::ExpandEnvironmentVariables($p).TrimEnd('\') -ieq $want) { return $true }
    }
    return $false
}

function Add-ToUserPath {
    if (Test-InUserPath) {
        [Console]::Error.WriteLine("$Dir is already on your user PATH. New terminals find ``conductor``.")
        return
    }
    $current = (Get-UserPath).TrimEnd(';')
    $new = if ($current) { "$current;$Dir" } else { $Dir }
    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value $new -Type ExpandString
    # Tell Explorer the environment changed, so newly opened terminals see it.
    Add-Type -Namespace ConductorSkills -Name Env -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    $r = [UIntPtr]::Zero
    [ConductorSkills.Env]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null
    [Console]::Error.WriteLine("Added $Dir to your user PATH. New terminals find ``conductor``; open terminals need restarting.")
}

function Found([string]$Path) {
    $inDir = (Split-Path -Parent $Path).TrimEnd('\') -ieq $Dir.TrimEnd('\')
    if ($inDir -and -not (Test-InUserPath)) {
        if ($AddToPath) { Add-ToUserPath }
        else { [Console]::Error.WriteLine("Note: $Dir is not on PATH, so ``conductor`` won't work in the user's terminals. Ask the user, then run: powershell -File `"$PSCommandPath`" -AddToPath  (adds it to the user PATH)") }
    } elseif ($AddToPath) {
        [Console]::Error.WriteLine("$(Split-Path -Parent $Path) is already on PATH; nothing to change.")
    }
    "CONDUCTOR_BIN=$Path"
    exit 0
}

$onPath = (Get-Command conductor -ErrorAction SilentlyContinue).Source
if (Test-Login $onPath) { Found $onPath }
if (Test-Login $Target) { Found $Target }

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
Found $Target
