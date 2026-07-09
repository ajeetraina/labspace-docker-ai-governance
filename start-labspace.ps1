<#
  start-labspace.ps1 - Launch the sbx Labspace on Windows (PowerShell)

  Best-effort Windows equivalent of start-labspace.sh, for users who want the
  embedded terminal panel on Windows. Run it from a normal PowerShell (5.1) or
  PowerShell 7+ (pwsh) prompt. See README "Running on Windows" for the
  supported path.

  IMPORTANT: sbx runs NATIVELY on Windows using the Windows Hypervisor Platform
  (winget install -h Docker.sbx). Do NOT run sbx inside WSL2 - that would force
  nested KVM, which Docker does not support for sbx. This script does not touch
  that; it only launches the labspace UI + a host ttyd terminal.

  Prerequisites (checked on startup):

    sbx (native Windows, Windows 11 x86_64):
      Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All  # then reboot
      winget install -h Docker.sbx
      # or download DockerSandboxes.msi from
      # https://github.com/docker/sbx-releases/releases

    ttyd (serves the right-hand terminal panel):
      scoop install ttyd
      # ttyd has no official winget package and native-Windows builds are
      # unreliable. If you can't install it, skip this launcher: open the lab
      # instructions at http://localhost:3030 in a browser and run sbx commands
      # in your own Windows Terminal / PowerShell instead.

    Docker Desktop must be running (provides `docker` + `docker compose`).

  If any prerequisite is missing, this script tells you what to install and
  exits cleanly.
#>

$ErrorActionPreference = 'Stop'

$TtydPort    = 8085
$ComposeFile = 'compose.override.yaml'

# -- Color helpers ------------------------------------------------
function Write-Info  { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "WARN: $Msg" -ForegroundColor Yellow }
function Write-ErrorAndExit {
  param([string]$Msg)
  Write-Host "ERROR: $Msg" -ForegroundColor Red
  exit 1
}

# Run from the script's own directory so relative paths resolve like the
# Bash version's `$(pwd)` assumption (repo root).
Set-Location -Path $PSScriptRoot

# -- 1. Check ttyd ------------------------------------------------
if (-not (Get-Command ttyd -ErrorAction SilentlyContinue)) {
  Write-Host ''
  Write-Host 'ERROR: ttyd not found.' -ForegroundColor Red
  Write-Host ''
  Write-Host '  Install it with:'
  Write-Host '    scoop install ttyd                 # Scoop'
  Write-Host '    # or run the Bash launcher under WSL2:'
  Write-Host '    #   wsl bash start-labspace.sh'
  Write-Host ''
  Write-Host '  Then re-run: pwsh -File start-labspace.ps1'
  exit 1
}

# -- 2. Check sbx -------------------------------------------------
if (-not (Get-Command sbx -ErrorAction SilentlyContinue)) {
  Write-Host ''
  Write-Host 'ERROR: sbx not found.' -ForegroundColor Red
  Write-Host ''
  Write-Host '  Install it with:'
  Write-Host '    winget install -h Docker.sbx'
  Write-Host '    # or the DockerSandboxes.msi from'
  Write-Host '    #   https://github.com/docker/sbx-releases/releases'
  Write-Host ''
  Write-Host '  Then re-run: pwsh -File start-labspace.ps1'
  exit 1
}

# -- 3. Ensure sbx daemon is running ------------------------------
#   `sbx daemon start` (no flags) runs in the FOREGROUND and blocks. Use
#   `-d` (detach). `sbx daemon status` exits 0 whether running OR stopped,
#   so key off the "Status: running" text, not the exit code.
function Test-DaemonRunning {
  try { (sbx daemon status 2>$null | Select-String 'Status: running') -ne $null }
  catch { $false }
}

if (Test-DaemonRunning) {
  Write-Info 'sbx daemon already running'
} else {
  Write-Info 'sbx daemon not running - starting it (detached)...'
  try { sbx daemon start -d *> $null } catch { }
  $started = $false
  foreach ($i in 1..15) {
    if (Test-DaemonRunning) { $started = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $started) {
    Write-ErrorAndExit "sbx daemon failed to start. Run 'sbx daemon start' manually to see the error."
  }
  Write-Info 'sbx daemon started'
}

$SbxVersion = (sbx version 2>$null) -join ' '
Write-Info "sbx version: $SbxVersion"

# -- 4. Set CONTENT_PATH -----------------------------------------
if (-not $env:CONTENT_PATH) { $env:CONTENT_PATH = (Get-Location).Path }
Write-Info "CONTENT_PATH set to: $($env:CONTENT_PATH)"

# Pin the Compose project name so the instructions volume has a
# deterministic name we can seed below.
if (-not $env:COMPOSE_PROJECT_NAME) {
  $env:COMPOSE_PROJECT_NAME = (Split-Path -Leaf (Get-Location).Path)
}
Write-Info "COMPOSE_PROJECT_NAME set to: $($env:COMPOSE_PROJECT_NAME)"

# -- 5. Validate compose.override.yaml exists --------------------
if (-not (Test-Path $ComposeFile)) {
  Write-ErrorAndExit "$ComposeFile not found. Are you running from the repo root?"
}

# -- 6. Clear port -----------------------------------------------
Write-Info "Clearing port $TtydPort..."
try {
  Get-NetTCPConnection -LocalPort $TtydPort -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }
} catch { }
Start-Sleep -Seconds 1

# -- 7. Start ttyd -----------------------------------------------
Write-Info "Starting terminal on port $TtydPort..."
# Expose a PowerShell shell in the right-hand panel (the Bash version uses zsh).
$ttydShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$ttydProc  = Start-Process -FilePath 'ttyd' `
  -ArgumentList @('-p', "$TtydPort", '--writable', '--max-clients', '4', $ttydShell) `
  -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 1

if (-not (Get-NetTCPConnection -LocalPort $TtydPort -ErrorAction SilentlyContinue)) {
  Write-ErrorAndExit "ttyd failed to start on port $TtydPort"
}
Write-Info "ttyd PID: $($ttydProc.Id)"

# -- 8. Pick base compose file (local, else OCI reference) -------
$BaseCompose = $null
foreach ($candidate in @('docker-compose.yml', 'compose.yaml', 'compose.yml')) {
  if (Test-Path $candidate) { $BaseCompose = $candidate; break }
}

# -- 8a. Seed the instructions volume ----------------------------
#   The dev-content flow copies ./ into /project but does NOT populate
#   /labspace/instructions, and Compose 'watch' only syncs on file *changes*.
#   Pre-seed so the interface finds labspace.yaml on first start.
$InstrVol = "$($env:COMPOSE_PROJECT_NAME)_labspace-instructions"
if (Test-Path 'labspace') {
  Write-Info "Seeding instructions volume ($InstrVol) from ./labspace..."
  docker volume create $InstrVol | Out-Null
  $labspacePath = (Resolve-Path 'labspace').Path
  docker run --rm `
    -v "${InstrVol}:/instructions" `
    -v "${labspacePath}:/src:ro" `
    alpine sh -c 'cp -a /src/. /instructions/'
} else {
  Write-Warn 'No ./labspace directory found - skipping instructions seed'
}

# -- 8b. Start Labspace ------------------------------------------
$composeArgs = @()
if ($BaseCompose) {
  Write-Info "Starting Labspace (local compose: $BaseCompose)..."
  $composeArgs = @('-f', $BaseCompose, '-f', $ComposeFile)
} else {
  Write-Info 'Starting Labspace (OCI reference)...'
  $composeArgs = @('-f', 'oci://dockersamples/labspace', '-f', $ComposeFile)
}

Write-Host ''
Write-Host '==========================================='
Write-Host '  Labspace ready at http://localhost:3030'
Write-Host '  Term 1 / Term 2  ->  your Windows terminal'
Write-Host '  Run: sbx ls, sbx version, sbx run ...'
Write-Host '==========================================='
Write-Host ''
Write-Host 'Press Ctrl+C to stop'

# -- 9. Cleanup on exit ------------------------------------------
try {
  docker compose @composeArgs up
} finally {
  Write-Host ''
  Write-Info 'Stopping...'
  if ($ttydProc -and -not $ttydProc.HasExited) {
    Stop-Process -Id $ttydProc.Id -Force -ErrorAction SilentlyContinue
  }
  try { docker compose @composeArgs down 2>$null } catch { }
}
