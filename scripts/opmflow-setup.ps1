# Requires -Version 5.1
<#
.SYNOPSIS
    OPM Flow Docker installer for Windows.

.DESCRIPTION
    Installs Docker Desktop if needed, pulls the OPM Flow image, and
    installs 'opmflow' and 'flow' commands on your PATH - the Windows
    counterpart to opmflow-setup.sh.

    Design differences from the Linux installer are deliberate, not
    oversights - see the comments through this file for why. The short
    version: this installs per-user (no Administrator rights needed for
    normal use, only Docker Desktop's own installer may prompt for UAC),
    since Windows has no root/sudo model and Docker Desktop itself runs
    per-user once installed.

.PARAMETER Version
    OPM Flow version: 'latest' or 'YYYY.MM'. Default: latest.

.PARAMETER Variant
    Image variant: auto, none, amd64, amd, arm64, nvidia. Default: auto.

.EXAMPLE
    .\opmflow-setup.ps1

.EXAMPLE
    .\opmflow-setup.ps1 -Version 2026.04 -Variant amd64
#>

[CmdletBinding()]
param(
  [string]$Version = "latest",
  [string]$Variant = "auto",
  [switch]$Help
)

$ErrorActionPreference = "Stop"

$script:ImageRepository = "openporousmedia/opmreleases"
$script:InstallDir = "$env:LOCALAPPDATA\opm-flow\bin"
$script:ConfigDir = "$env:LOCALAPPDATA\opm-flow"
$script:ConfigFile = "$ConfigDir\config"
$script:DockerDesktopExe = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"

function Write-Log {
  param([string]$Message)
  Write-Host "[opm-flow] $Message"
}

function Write-WarnLog {
  param([string]$Message)
  Write-Host "[opm-flow] warning: $Message" -ForegroundColor Yellow
}

function Die {
  param([string]$Message)
  Write-Host "[opm-flow] error: $Message" -ForegroundColor Red
  exit 1
}

function Show-Help {
  @"
OPM Flow Docker installer (Windows)

Usage:

    .\opmflow-setup.ps1
    .\opmflow-setup.ps1 -Version latest
    .\opmflow-setup.ps1 -Version 2026.04

    .\opmflow-setup.ps1 -Variant auto
    .\opmflow-setup.ps1 -Variant amd64
    .\opmflow-setup.ps1 -Variant arm64
    .\opmflow-setup.ps1 -Variant nvidia
    .\opmflow-setup.ps1 -Variant none

    .\opmflow-setup.ps1 -Version latest -Variant nvidia

Options:

    -Version VERSION   OPM Flow version. 'latest' or 'YYYY.MM'.
                        Default: latest
    -Variant VARIANT   Image variant/suffix.
                        Supported: auto, none, amd64, amd, arm64, nvidia
                        Default: auto
    -Help              Show this help and exit

No Administrator rights are needed to run this installer under normal
circumstances - it installs per-user under `$env:LOCALAPPDATA. Docker
Desktop's own installer may still prompt for UAC elevation if Docker
isn't already installed; that prompt comes from Docker's installer,
not this script.

This installer requires the WSL2 backend (Docker Desktop's default and
recommended mode on Windows 10/11). If WSL2 isn't set up yet, run
'wsl --install' from an elevated prompt and reboot before continuing.
"@
}

#
# ---------------------------------------------------------------------
# Version / variant validation and image resolution
# ---------------------------------------------------------------------
#

function Test-Version {
  param([string]$VersionToCheck)

  if ($VersionToCheck -eq "latest") {
    return
  }

  if ($VersionToCheck -notmatch '^\d{4}\.\d{2}$') {
    Die @"
Invalid OPM Flow version: $VersionToCheck

Expected:

    latest
    YYYY.MM

Examples:

    latest
    2026.04
"@
  }
}

function Test-Variant {
  param([string]$VariantToCheck)

  if ($VariantToCheck -notin @("auto", "none", "amd", "amd64", "arm64", "nvidia")) {
    Die @"
Unsupported OPM Flow variant: $VariantToCheck

Supported variants:

    auto
    none
    amd
    amd64
    arm64
    nvidia
"@
  }
}

#
# RuntimeInformation.OSArchitecture is the
# reliable cross-version way to get the actual OS architecture (as
# opposed to $env:PROCESSOR_ARCHITECTURE, which reports the process's
# architecture and can misreport under WOW64 - a 32-bit PowerShell
# host on a 64-bit OS would see 'x86' from the env var but this API
# still correctly reports the OS as X64/Arm64).
#
function Get-HostVariant {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

  switch ($arch) {
    "X64" { return "amd64" }
    "Arm64" { return "arm64" }
    default {
      Die @"
Unable to determine an automatic OPM Flow variant from: $arch

Specify one explicitly:

    -Variant amd64
    -Variant amd
    -Variant arm64
    -Variant nvidia
    -Variant none
"@
    }
  }
}

function Get-ImageForVariant {
  param([string]$ImgVersion, [string]$ImgVariant)

  if ($ImgVariant -eq "none") {
    return "${ImageRepository}:${ImgVersion}"
  }

  return "${ImageRepository}:${ImgVersion}_${ImgVariant}"
}

function Test-ImageExistsLocally {
  param([string]$Image)

  docker image inspect $Image *> $null
  return $LASTEXITCODE -eq 0
}

function Test-ImageExistsRemotely {
  param([string]$Image)

  # docker manifest inspect asks the registry whether a tag exists
  # and returns its manifest without downloading any image layers
  $env:DOCKER_CLI_EXPERIMENTAL = "enabled"
  try {
    docker manifest inspect $Image *> $null
    return $LASTEXITCODE -eq 0
  }
  finally {
    Remove-Item Env:\DOCKER_CLI_EXPERIMENTAL -ErrorAction SilentlyContinue
  }
}

function Try-ResolveImage {
  param([string]$Image)

  Write-Log "Checking $Image..."

  return (Test-ImageExistsLocally $Image) -or (Test-ImageExistsRemotely $Image)
}

function Invoke-PullImage {
  param([string]$Image)

  if (Test-ImageExistsLocally $Image) {
    Write-Log "Image already present locally, skipping pull: $Image"
    return
  }

  Write-Log "Pulling $Image..."

  docker pull $Image
  if ($LASTEXITCODE -ne 0) {
    Die "Unable to pull Docker image:`n`n    $Image"
  }
}

function Resolve-Image {
  param([string]$ImgVersion, [string]$ImgVariant)

  Test-Version $ImgVersion
  Test-Variant $ImgVariant

  # Explicitly request the unsuffixed image.
  if ($ImgVariant -eq "none") {
    $image = "${ImageRepository}:${ImgVersion}"
    if (-not (Try-ResolveImage $image)) {
      Die "OPM Flow image does not exist:`n`n    $image"
    }
    return $image
  }

  # Explicit variant - never silently fall back to another variant.
  if ($ImgVariant -ne "auto") {
    $image = Get-ImageForVariant $ImgVersion $ImgVariant
    if (-not (Try-ResolveImage $image)) {
      Die "OPM Flow image does not exist:`n`n    $image`n`nRequested variant:`n`n    $ImgVariant`n`nUse -Variant auto to allow automatic resolution."
    }
    return $image
  }

  # Automatic resolution.
  $hostVariant = Get-HostVariant
  Write-Log "Automatic variant selected: $hostVariant"

  $candidate = Get-ImageForVariant $ImgVersion $hostVariant
  if (Try-ResolveImage $candidate) {
    return $candidate
  }

  # Older releases may not have a variant suffix.
  $fallback = "${ImageRepository}:${ImgVersion}"
  Write-Log "Variant-specific image unavailable; trying unsuffixed image."

  if (Try-ResolveImage $fallback) {
    return $fallback
  }

  Die "Unable to find an OPM Flow image for version ${ImgVersion}.`n`nTried:`n`n    $candidate`n    $fallback`n`nSpecify an explicit variant if appropriate."
}

function Get-LatestVersionNumber {
  # Determine the latest published OPM Flow version without pulling any image.
  try {
    $url = "https://hub.docker.com/v2/repositories/${ImageRepository}/tags?page_size=100&ordering=-last_updated"
    $response = Invoke-RestMethod -Uri $url -Method Get

    $versions = $response.results |
      ForEach-Object { $_.name } |
      Where-Object { $_ -match '^\d{4}\.\d{2}(_[A-Za-z0-9]+)?$' } |
      ForEach-Object { ($_ -split '_')[0] } |
      Sort-Object -Descending -Unique

    if ($versions.Count -gt 0) {
      return $versions[0]
    }
    return $null
  }
  catch {
    return $null
  }
}

function Invoke-RunFlowVersion {
  param([string]$Image)

  return (docker run --rm $Image flow --version 2>&1 | Out-String).Trim()
}

function Get-VersionFromOutput {
  param([string]$Output)

  if ($Output -match '(\d{4}\.\d{2})') {
    return $Matches[1]
  }
  return $null
}

#
# ---------------------------------------------------------------------
# Docker Desktop detection, install, and readiness
# ---------------------------------------------------------------------
#

function Test-DockerCommand {
  return [bool](Get-Command docker -ErrorAction SilentlyContinue)
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Wsl2Available {
  try {
    $status = wsl.exe --status 2>&1 | Out-String
    return $LASTEXITCODE -eq 0
  }
  catch {
    return $false
  }
}

function Install-Docker {
  if (Test-DockerCommand) {
    Write-Log "Docker found: $(docker --version)"
    return
  }

  Write-Log "Docker is not installed."

  if (-not (Test-Wsl2Available)) {
    Write-WarnLog @"
WSL2 does not appear to be set up. Docker Desktop's default backend on
Windows requires it. If Docker Desktop fails to start after install,
open an elevated PowerShell and run:

    wsl --install

then reboot and try again.
"@
  }

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    Die @"
winget was not found, so Docker Desktop can't be installed
automatically.

Install it manually from:

    https://www.docker.com/products/docker-desktop/

Then re-run this installer.
"@
  }

  Write-Log "Installing Docker Desktop via winget (this may prompt for administrator approval)..."

  winget install --exact --id Docker.DockerDesktop `
    --accept-package-agreements --accept-source-agreements

  if ($LASTEXITCODE -ne 0) {
    Die @"
winget install of Docker Desktop failed (exit code $LASTEXITCODE).

Install it manually from:

    https://www.docker.com/products/docker-desktop/

Then re-run this installer.
"@
  }

  if (-not (Test-DockerCommand)) {
    Write-WarnLog @"
Docker Desktop was installed, but the 'docker' command isn't on PATH
yet in this session. Close this window, open a new PowerShell prompt,
and re-run this installer.
"@
    exit 1
  }
}

function Wait-DockerReady {
  param([int]$TimeoutSeconds = 90)

  if (docker info *> $null; $LASTEXITCODE -eq 0) {
    return
  }

  if (Test-Path $DockerDesktopExe) {
    Write-Log "Docker daemon not responding - starting Docker Desktop..."
    Start-Process -FilePath $DockerDesktopExe | Out-Null
  }
  else {
    Die @"
Docker is installed but the daemon isn't responding, and Docker
Desktop wasn't found at the expected location:

    $DockerDesktopExe

Start Docker Desktop manually from the Start Menu, wait for it to
report "Engine running", then re-run this installer.
"@
  }

  Write-Log "Waiting for Docker Desktop to finish starting (up to ${TimeoutSeconds}s)..."

  $elapsed = 0
  $interval = 3
  while ($elapsed -lt $TimeoutSeconds) {
    Start-Sleep -Seconds $interval
    $elapsed += $interval

    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Log "Docker is ready."
      return
    }
  }

  Die @"
Docker Desktop did not become ready within ${TimeoutSeconds}s.

This commonly means:

  - Docker Desktop is waiting on its first-run setup or a license
    prompt. Check for a Docker Desktop window and complete it.
  - WSL2 isn't installed/enabled. Run 'wsl --install' from an
    elevated command prompt, reboot, then re-run this installer.
  - Docker Desktop is set to Windows containers instead of Linux
    containers. Right-click the Docker tray icon and choose
    "Switch to Linux containers...". OPM Flow's images are Linux-only.

Once Docker Desktop shows "Engine running", re-run this installer.
"@
}

function Test-LinuxContainerMode {
  try {
    $os = (docker version --format '{{.Server.Os}}' 2>&1 | Out-String).Trim()
    if ($os -eq "windows") {
      Die @"
Docker Desktop is running in Windows containers mode. OPM Flow's
images are Linux-only.

Right-click the Docker Desktop tray icon and choose
"Switch to Linux containers...", then re-run this installer.
"@
    }
  }
  catch {
    # Non-fatal: if the format query itself fails, let downstream
    # pull/run steps surface the real error instead of masking it
    # here with a diagnostic-only check.
  }
}

#
# ---------------------------------------------------------------------
# Config file
# ---------------------------------------------------------------------
#

function Write-OpmConfig {
  param([string]$CfgVersion, [string]$CfgVariant, [string]$CfgImage)

  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

  @"
OPM_FLOW_VERSION=$CfgVersion
OPM_FLOW_VARIANT=$CfgVariant
OPM_FLOW_IMAGE=$CfgImage
"@ | Set-Content -Path $ConfigFile -Encoding UTF8
}

#
# ---------------------------------------------------------------------
# Wrapper installation
#
# Writes opmflow.ps1 (the real logic) plus .cmd shims for opmflow and
# flow so both PowerShell and cmd.exe users get a plain 'opmflow' /
# 'flow' command. Windows can't create symlinks without either
# Administrator rights or Developer Mode enabled (unlike 'ln -sf' on
# Linux, which needs neither) - a second small shim file sidesteps
# that entirely instead of depending on either.
# ---------------------------------------------------------------------
#

function Install-Wrapper {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $wrapperContent = @'
$ErrorActionPreference = "Stop"

$script:ConfigFile = "$env:LOCALAPPDATA\opm-flow\config"
$script:ImageRepository = "openporousmedia/opmreleases"

function Write-Log { param([string]$Message) Write-Host "[opm-flow] $Message" }
function Write-WarnLog { param([string]$Message) Write-Host "[opm-flow] warning: $Message" -ForegroundColor Yellow }
function Die { param([string]$Message) Write-Host "[opm-flow] error: $Message" -ForegroundColor Red; exit 1 }

function Test-DockerCommand {
    return [bool](Get-Command docker -ErrorAction SilentlyContinue)
}

function Get-OpmConfig {
    if (-not (Test-Path $ConfigFile)) {
        Die "OPM Flow is not configured.`n`nRun the installer first:`n`n    .\opmflow-setup.ps1"
    }

    $config = @{}
    Get-Content $ConfigFile | ForEach-Object {
        if ($_ -match '^([A-Z_]+)=(.*)$') {
            $config[$Matches[1]] = $Matches[2]
        }
    }

    foreach ($key in @("OPM_FLOW_VERSION", "OPM_FLOW_VARIANT", "OPM_FLOW_IMAGE")) {
        if (-not $config.ContainsKey($key)) {
            Die "Missing $key in $ConfigFile"
        }
    }

    return $config
}

function Test-Version {
    param([string]$VersionToCheck)
    if ($VersionToCheck -notmatch '^\d{4}\.\d{2}$') {
        Die "Invalid OPM Flow version: $VersionToCheck"
    }
}

function Test-Variant {
    param([string]$VariantToCheck)
    if ($VariantToCheck -notin @("auto", "none", "amd", "amd64", "arm64", "nvidia")) {
        Die "Unsupported OPM Flow variant: $VariantToCheck"
    }
}

function Get-HostVariant {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch) {
        "X64" { return "amd64" }
        "Arm64" { return "arm64" }
        default { Die "Unable to determine an automatic OPM Flow variant from: $arch" }
    }
}

function Get-ImageForVariant {
    param([string]$ImgVersion, [string]$ImgVariant)
    if ($ImgVariant -eq "none") { return "${ImageRepository}:${ImgVersion}" }
    return "${ImageRepository}:${ImgVersion}_${ImgVariant}"
}

function Test-ImageExistsLocally {
    param([string]$Image)
    docker image inspect $Image *> $null
    return $LASTEXITCODE -eq 0
}

function Test-ImageExistsRemotely {
    param([string]$Image)
    $env:DOCKER_CLI_EXPERIMENTAL = "enabled"
    try {
        docker manifest inspect $Image *> $null
        return $LASTEXITCODE -eq 0
    }
    finally {
        Remove-Item Env:\DOCKER_CLI_EXPERIMENTAL -ErrorAction SilentlyContinue
    }
}

function Try-ResolveImage {
    param([string]$Image)
    Write-Log "Checking $Image..."
    return (Test-ImageExistsLocally $Image) -or (Test-ImageExistsRemotely $Image)
}

function Invoke-PullImage {
    param([string]$Image)
    if (Test-ImageExistsLocally $Image) {
        Write-Log "Image already present locally, skipping pull: $Image"
        return
    }
    Write-Log "Pulling $Image..."
    docker pull $Image
    if ($LASTEXITCODE -ne 0) { Die "Unable to pull:`n`n    $Image" }
}

function Test-ImageAvailable {
    param([hashtable]$Config)
    if (-not (Test-ImageExistsLocally $Config.OPM_FLOW_IMAGE)) {
        Write-Log "Configured OPM Flow image is not available locally."
        Invoke-PullImage $Config.OPM_FLOW_IMAGE
    }
}

function Invoke-RunFlowVersion {
    param([string]$Image)
    return (docker run --rm $Image flow --version 2>&1 | Out-String).Trim()
}

function Get-VersionFromOutput {
    param([string]$Output)
    if ($Output -match '(\d{4}\.\d{2})') { return $Matches[1] }
    return $null
}

function Get-LatestVersionNumber {
    try {
        $url = "https://hub.docker.com/v2/repositories/${ImageRepository}/tags?page_size=100&ordering=-last_updated"
        $response = Invoke-RestMethod -Uri $url -Method Get
        $versions = $response.results |
            ForEach-Object { $_.name } |
            Where-Object { $_ -match '^\d{4}\.\d{2}(_[A-Za-z0-9]+)?$' } |
            ForEach-Object { ($_ -split '_')[0] } |
            Sort-Object -Descending -Unique
        if ($versions.Count -gt 0) { return $versions[0] }
        return $null
    }
    catch {
        return $null
    }
}

function Show-Version {
    param([hashtable]$Config)
    Test-ImageAvailable $Config
    Invoke-RunFlowVersion $Config.OPM_FLOW_IMAGE
}

function Show-Image { param([hashtable]$Config) $Config.OPM_FLOW_IMAGE }
function Show-Variant { param([hashtable]$Config) $Config.OPM_FLOW_VARIANT }
function Show-Config { Get-Content $ConfigFile }

function Invoke-UpgradeToVersion {
    param([string]$TargetVersion, [hashtable]$Config)

    Test-Version $TargetVersion

    $variant = $Config.OPM_FLOW_VARIANT
    $image = $null

    if ($variant -eq "none") {
        $image = "${ImageRepository}:${TargetVersion}"
    }
    elseif ($variant -ne "auto") {
        $image = "${ImageRepository}:${TargetVersion}_${variant}"
    }
    else {
        $hostVariant = Get-HostVariant
        $candidate = "${ImageRepository}:${TargetVersion}_${hostVariant}"

        if (Try-ResolveImage $candidate) {
            $image = $candidate
        }
        else {
            $image = "${ImageRepository}:${TargetVersion}"
            if (-not (Try-ResolveImage $image)) {
                Die "Unable to find an OPM Flow image for:`n`n    $TargetVersion`n`nTried:`n`n    $candidate`n    $image"
            }
        }
    }

    Invoke-PullImage $image
    Write-OpmConfig -CfgVersion $TargetVersion -CfgVariant $variant -CfgImage $image

    Write-Log "OPM Flow $TargetVersion is now pinned."
    Write-Log "Image: $image"
}

function Write-OpmConfig {
    param([string]$CfgVersion, [string]$CfgVariant, [string]$CfgImage)
    @"
OPM_FLOW_VERSION=$CfgVersion
OPM_FLOW_VARIANT=$CfgVariant
OPM_FLOW_IMAGE=$CfgImage
"@ | Set-Content -Path $ConfigFile -Encoding UTF8
}

function Invoke-UpgradeToLatest {
    param([hashtable]$Config)

    Write-Log "Determining latest OPM Flow version..."

    $ver = Get-LatestVersionNumber
    if ($ver) {
        Write-Log "Latest OPM Flow release (from registry API): $ver"
        Invoke-UpgradeToVersion -TargetVersion $ver -Config $Config
        return
    }

    Write-WarnLog "Could not reach the registry API; falling back to pulling :latest to read its version."

    $latestImage = "${ImageRepository}:latest"
    Invoke-PullImage $latestImage

    $output = Invoke-RunFlowVersion $latestImage
    $ver = Get-VersionFromOutput $output
    if (-not $ver) {
        Die "Unable to determine the OPM Flow version from:`n`n$output"
    }

    Write-Log "Latest OPM Flow release: $ver"
    Invoke-UpgradeToVersion -TargetVersion $ver -Config $Config
}

function Invoke-ConfigureVariant {
    param([string]$NewVariant, [hashtable]$Config)

    Test-Variant $NewVariant

    $ver = $Config.OPM_FLOW_VERSION
    $image = $null
    $effectiveVariant = $NewVariant

    if ($NewVariant -eq "none") {
        $image = "${ImageRepository}:${ver}"
    }
    elseif ($NewVariant -ne "auto") {
        $image = "${ImageRepository}:${ver}_${NewVariant}"
    }
    else {
        $hostVariant = Get-HostVariant
        $image = "${ImageRepository}:${ver}_${hostVariant}"

        Write-Log "Trying $image..."
        if (-not (Try-ResolveImage $image)) {
            $image = "${ImageRepository}:${ver}"
            Write-Log "Falling back to $image..."
            Invoke-PullImage $image
        }
    }

    if ($NewVariant -ne "auto") {
        Invoke-PullImage $image
    }

    Write-OpmConfig -CfgVersion $ver -CfgVariant $effectiveVariant -CfgImage $image

    Write-Log "OPM Flow variant changed to $effectiveVariant."
    Write-Log "Image: $image"
}

function Show-Help {
    param([hashtable]$Config)
    @"
OPM Flow Docker wrapper

Run OPM Flow:

    flow SPE1.DATA
    opmflow SPE1.DATA

All arguments not listed below are passed directly to OPM Flow. If a
filename has spaces, quote it with double quotes - PowerShell's escape
character is the backtick (``), not a backslash, so a backslash-escaped
space (as you'd write in bash) will NOT work here and will be passed
through literally:

    flow "My Field.DATA"       # correct
    flow My\ Field.DATA        # wrong on Windows - backslash is not
                                # an escape character in PowerShell

Management commands:

    opmflow version
        Display the configured OPM Flow version.

    opmflow image
        Display the configured Docker image.

    opmflow variant
        Display the configured variant.

    opmflow config
        Display the current configuration.

    opmflow upgrade
        Resolve the latest release and pin it.

    opmflow upgrade VERSION
        Resolve and pin VERSION.

    opmflow configure --variant VARIANT
        Change the configured variant.

Variants:

    auto     Automatically choose the host-compatible image.
             Falls back to the unsuffixed image for older releases.
    amd64    Use VERSION_amd64.
    amd      Use VERSION_amd.
    arm64    Use VERSION_arm64.
    nvidia   Use VERSION_nvidia.
    none     Use VERSION without a suffix.

Examples:

    flow SPE1.DATA
    flow --help
    flow --version

    opmflow version
    opmflow upgrade
    opmflow upgrade 2026.04
    opmflow configure --variant amd64

Current configuration:

    Version: $($Config.OPM_FLOW_VERSION)
    Variant: $($Config.OPM_FLOW_VARIANT)
    Image:   $($Config.OPM_FLOW_IMAGE)
"@
}

function Invoke-RunFlow {
  param([hashtable]$Config, [string[]]$FlowArgs)

  Test-ImageAvailable $Config

  # Resolve-Path handles relative paths, '.', and reparse points
  # (junctions/symlinks) the way 'pwd -P' does on Linux.
  $workdir = (Resolve-Path -LiteralPath .).Path

  # Docker Desktop's Windows docker.exe CLI accepts a native Windows
  # path directly for -v and translates it internally - unlike
  # legacy Docker Toolbox, no manual /c/Users/... conversion is
  # needed here.
  #
  # No '--user uid:gid': Windows has no POSIX UID/GID to hand the
  # container, and there's no host/container permission-alignment
  # concern here the way there is natively on Linux - fabricating a
  # uid would just as likely cause a mismatch as prevent one, so the
  # container runs as whichever user its image defines by default.
  $mountSpec = "${workdir}:/simulation"

  docker run --rm `
    --init `
    --workdir /simulation `
    --volume $mountSpec `
    $Config.OPM_FLOW_IMAGE `
    flow @FlowArgs

  exit $LASTEXITCODE
}

function Main {
  if (-not (Test-DockerCommand)) {
    Die "Docker is not installed."
  }

  $config = Get-OpmConfig

  $command = $args[0]
  $rest = @()
  if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

  switch ($command) {
    "upgrade" {
      if ($rest.Count -eq 0) {
        Invoke-UpgradeToLatest -Config $config
      }
      elseif ($rest.Count -eq 1) {
        Invoke-UpgradeToVersion -TargetVersion $rest[0] -Config $config
      }
      else {
        Die "Usage:`n`n    opmflow upgrade`n    opmflow upgrade VERSION"
      }
    }
    "configure" {
      if ($rest.Count -eq 2 -and $rest[0] -eq "--variant") {
        Invoke-ConfigureVariant -NewVariant $rest[1] -Config $config
      }
      else {
        Die "Usage:`n`n    opmflow configure --variant VARIANT"
      }
    }
    { $_ -in @("version", "--version") } { Show-Version -Config $config }
    "image" { Show-Image -Config $config }
    "variant" { Show-Variant -Config $config }
    "config" { Show-Config }
    { $_ -in @("help", "--help", "-h", $null) } { Show-Help -Config $config }
    default { Invoke-RunFlow -Config $config -FlowArgs $args }
  }
}

Main @args
'@
