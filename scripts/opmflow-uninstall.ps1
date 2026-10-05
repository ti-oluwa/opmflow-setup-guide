#Requires -Version 5.1
<#
.SYNOPSIS
    OPM Flow uninstaller for Windows.

.DESCRIPTION
    The counterpart to opmflow-setup.ps1. Removes only what that
    installer put on this computer:

        %LOCALAPPDATA%\opm-flow\bin    the 'opmflow' and 'flow' commands
        %LOCALAPPDATA%\opm-flow        the saved version/variant settings
        your user PATH                 the one entry pointing at the bin folder
        the OPM Flow Docker images that were downloaded

    What it deliberately does NOT touch:

      - Docker Desktop and WSL2. The installer does not record whether
        it was the one that installed them, and both are commonly used
        for other things, so removing them automatically could break
        unrelated work. The README explains how to remove them yourself.
      - Your simulation files (.DATA files, results).
      - Anything outside your own user account. No Administrator rights
        are needed, and the system-wide PATH is never touched.

    The PATH edit is the one delicate step, so it is done carefully: only
    the exact entry the installer added is removed, every other entry is
    kept exactly as it was (including ones that use %VARIABLES%), and a
    backup of your PATH is saved first.

.PARAMETER DryRun
    Show what would be removed, and change nothing.

.PARAMETER KeepImages
    Remove the commands and settings, but keep the downloaded Docker
    images (they can be large, but keeping them makes a later reinstall
    much faster).

.PARAMETER Yes
    Do not ask for confirmation. Useful in scripts.

.EXAMPLE
    .\opmflow-uninstall.ps1 -DryRun

.EXAMPLE
    .\opmflow-uninstall.ps1

.EXAMPLE
    .\opmflow-uninstall.ps1 -KeepImages -Yes
#>

[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$KeepImages,
  [switch]$Yes,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

$script:ImageRepository = "openporousmedia/opmreleases"
# [IO.Path]::Combine (unlike Join-Path) does not throw a raw error if
# LOCALAPPDATA is somehow unset, so Main can give a friendly message.
$script:ConfigDir = [IO.Path]::Combine("$env:LOCALAPPDATA", "opm-flow")
$script:InstallDir = [IO.Path]::Combine($script:ConfigDir, "bin")
$script:ConfigFile = [IO.Path]::Combine($script:ConfigDir, "config")

# The four files opmflow-setup.ps1 writes into the bin folder.
$script:WrapperFiles = @("opmflow.ps1", "opmflow.cmd", "flow.cmd", "flow.ps1")

# What Find-Installation fills in.
$script:FoundFiles = @()
$script:OtherFilesInBin = @()
$script:BinDirExists = $false
$script:ConfigFileExists = $false
$script:ConfigDirExists = $false
$script:PathPlan = $null
$script:PathProblem = $null
$script:BackupPath = $null
$script:DockerState = "unknown"   # ready | missing | not_running
$script:Images = @()

$script:Done = New-Object System.Collections.Generic.List[string]
$script:Left = New-Object System.Collections.Generic.List[string]
$script:Failures = 0

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

function Write-Plan {
  param([string]$Action, [string]$Text)
  Write-Log ("    {0,-9} {1}" -f $Action, $Text)
}

function Show-Help {
  @"
OPM Flow uninstaller (Windows)

Removes what opmflow-setup.ps1 installed:

    $script:InstallDir
    $script:ConfigDir
    the entry for that folder in your user PATH
    the downloaded OPM Flow Docker images ($script:ImageRepository)

It does NOT remove Docker Desktop or WSL2, and it does not touch your
simulation files. See the README for how to remove those separately if
you want to.

No Administrator rights are needed.

Usage:

    .\opmflow-uninstall.ps1 [options]

Options:

    -DryRun        Show what would be removed, and change nothing.
    -KeepImages    Remove the commands and settings, but keep the
                   downloaded Docker images (they can be large, but
                   keeping them makes a later reinstall much faster).
    -Yes           Do not ask for confirmation. Useful in scripts.
    -Help          Show this help and exit

Examples:

    .\opmflow-uninstall.ps1 -DryRun
    .\opmflow-uninstall.ps1
    .\opmflow-uninstall.ps1 -KeepImages
    .\opmflow-uninstall.ps1 -Yes
"@
}

#
# ---------------------------------------------------------------------
# PATH handling
#
# Windows keeps the user PATH in the registry, and the value can be a
# plain string or an "expandable" string that contains %VARIABLES%
# (for example %USERPROFILE%\bin). The convenient .NET calls
# GetEnvironmentVariable/SetEnvironmentVariable quietly expand those
# variables into fixed text and rewrite the value as a plain string, so
# a round trip through them subtly changes entries that have nothing to
# do with this uninstaller. To avoid that, the raw value is read with
# expansion switched off, edited as plain text, and written back with
# its original type. Only entries that match exactly are removed.
# ---------------------------------------------------------------------
#

function Get-UserPathRaw {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
  if ($null -eq $key) {
    return $null
  }

  try {
    return [string]$key.GetValue("Path", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  }
  finally {
    $key.Close()
  }
}

function Set-UserPathRaw {
  param([string]$Value)

  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
  if ($null -eq $key) {
    throw "Could not open your user environment settings for writing."
  }

  try {
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    try {
      $kind = $key.GetValueKind("Path")
    }
    catch {
      # Keep the default if the existing type cannot be read.
    }

    $key.SetValue("Path", $Value, $kind)
  }
  finally {
    $key.Close()
  }
}

#
# Writing the registry directly does not tell already-running programs
# (like Explorer, which launches new terminals) that the environment
# changed. Setting and then deleting a throwaway user variable through
# .NET makes Windows broadcast that change, without needing any
# low-level calls here.
#
function Send-EnvironmentChange {
  try {
    $name = "OPM_FLOW_UNINSTALL_NOTIFY"
    [Environment]::SetEnvironmentVariable($name, "1", "User")
    [Environment]::SetEnvironmentVariable($name, $null, "User")
  }
  catch {
    Write-WarnLog "Could not notify Windows about the PATH change. Sign out and back in, or open a new terminal, for it to take effect."
  }
}

#
# Only used to COMPARE entries. Retained entries are always written
# back exactly as they were found.
#
function ConvertTo-ComparablePath {
  param([string]$PathText)

  if ([string]::IsNullOrWhiteSpace($PathText)) {
    return ""
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($PathText.Trim().Trim('"'))

  return $expanded.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function Split-PathEntries {
  param([string]$PathValue, [scriptblock]$ShouldRemove)

  $kept = New-Object System.Collections.Generic.List[string]
  $removed = New-Object System.Collections.Generic.List[string]

  foreach ($entry in $PathValue.Split(';')) {
    $comparable = ConvertTo-ComparablePath $entry

    if ($comparable -ne "" -and (& $ShouldRemove $comparable)) {
      [void]$removed.Add($entry)
    }
    else {
      [void]$kept.Add($entry)
    }
  }

  return [pscustomobject]@{
    NewValue = ($kept.ToArray() -join ';')
    Removed  = $removed.ToArray()
  }
}

function Get-UserPathPlan {
  param([scriptblock]$ShouldRemove)

  $raw = Get-UserPathRaw

  if ([string]::IsNullOrEmpty($raw)) {
    return $null
  }

  $result = Split-PathEntries -PathValue $raw -ShouldRemove $ShouldRemove

  if ($result.Removed.Count -eq 0) {
    return $null
  }

  return [pscustomobject]@{
    Raw      = $raw
    NewValue = $result.NewValue
    Removed  = $result.Removed
  }
}

function Test-InstallPathEntry {
  param([string]$Comparable)

  return $Comparable -eq (ConvertTo-ComparablePath $script:InstallDir)
}

#
# ---------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------
#

#
# Runs docker and captures its output and exit code without letting a
# harmless message on stderr turn into a script-stopping error (which
# Windows PowerShell 5.1 does when $ErrorActionPreference is "Stop").
#
function Invoke-Docker {
  param([string[]]$DockerArgs)

  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"

  try {
    $output = & docker @DockerArgs 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previous
  }

  return [pscustomobject]@{
    ExitCode = $code
    Output   = @($output | Where-Object { $null -ne $_ })
  }
}

#
# Never starts Docker Desktop. An uninstaller that launches a large
# application as a side effect would be a surprise.
#
function Find-DockerState {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $script:DockerState = "missing"
    return
  }

  $info = Invoke-Docker @("info")

  if ($info.ExitCode -eq 0) {
    $script:DockerState = "ready"
  }
  else {
    $script:DockerState = "not_running"
  }
}

#
# Finds every local image from the OPM Flow repository, not just the
# one pinned in the config. Each 'opmflow upgrade' pulls a new image
# and leaves the previous one behind. Every line is checked against a
# strict pattern before it is passed to 'docker rmi'. Untagged
# leftovers (<none>) fail the pattern and are skipped.
#
function Find-Images {
  $listing = Invoke-Docker @("image", "ls", "--format", "{{.Repository}}:{{.Tag}}", $script:ImageRepository)

  if ($listing.ExitCode -ne 0) {
    return @()
  }

  return @($listing.Output |
      Where-Object { $_ -match '^openporousmedia/opmreleases:[A-Za-z0-9_.-]+$' } |
      Sort-Object -Unique)
}

#
# ---------------------------------------------------------------------
# Inspect, plan, confirm
# ---------------------------------------------------------------------
#

function Find-Installation {
  $script:BinDirExists = Test-Path -LiteralPath $script:InstallDir -PathType Container

  if ($script:BinDirExists) {
    foreach ($name in $script:WrapperFiles) {
      if (Test-Path -LiteralPath (Join-Path $script:InstallDir $name) -PathType Leaf) {
        $script:FoundFiles += $name
      }
    }

    $script:OtherFilesInBin = @(Get-ChildItem -LiteralPath $script:InstallDir -Force |
        Where-Object { $script:WrapperFiles -notcontains $_.Name } |
        ForEach-Object { $_.Name })
  }

  $script:ConfigDirExists = Test-Path -LiteralPath $script:ConfigDir -PathType Container
  $script:ConfigFileExists = Test-Path -LiteralPath $script:ConfigFile -PathType Leaf

  try {
    $script:PathPlan = Get-UserPathPlan -ShouldRemove { param($c) Test-InstallPathEntry $c }
  }
  catch {
    $script:PathProblem = $_.Exception.Message
  }

  if (-not $KeepImages) {
    Find-DockerState

    if ($script:DockerState -eq "ready") {
      $script:Images = @(Find-Images)
    }
  }
}

function Test-NothingToRemove {
  return ($script:FoundFiles.Count -eq 0) -and
  (-not $script:ConfigFileExists) -and
  ($null -eq $script:PathPlan) -and
  ($script:Images.Count -eq 0)
}

function Show-Plan {
  Write-Log "OPM Flow uninstaller"
  Write-Log ""
  Write-Log "Found on this computer:"
  Write-Log ""

  foreach ($name in $script:FoundFiles) {
    Write-Plan "remove" "$(Join-Path $script:InstallDir $name)"
  }

  foreach ($name in $script:OtherFilesInBin) {
    Write-Plan "keep" "$(Join-Path $script:InstallDir $name)   (not created by the OPM Flow installer)"
  }

  if ($script:ConfigFileExists) {
    Write-Plan "remove" "$script:ConfigFile   (saved version and variant settings)"
  }

  if ($script:PathPlan) {
    foreach ($entry in $script:PathPlan.Removed) {
      Write-Plan "remove" "$entry   (entry in your user PATH; a backup is saved first)"
    }
  }

  if ($script:PathProblem) {
    Write-Plan "skip" "user PATH   (could not be read: $($script:PathProblem))"
  }

  foreach ($image in $script:Images) {
    Write-Plan "remove" "Docker image $image"
  }

  if ($KeepImages) {
    Write-Plan "keep" "Docker images   (because -KeepImages was given)"
  }
  elseif ($script:DockerState -eq "not_running") {
    Write-Plan "skip" "Docker images   (Docker Desktop is installed but not running)"
  }
  elseif ($script:DockerState -eq "missing") {
    Write-Plan "skip" "Docker images   (Docker was not found)"
  }

  Write-Log ""
  Write-Log "Not touched, on purpose:"
  Write-Log "    - Docker Desktop and WSL2"
  Write-Log "    - your simulation files (.DATA files and results)"
  Write-Log ""
}

#
# Asks in the console. If this window cannot ask (for example it was
# started with -NonInteractive), refuse to guess and ask for -Yes.
#
function Confirm-Proceed {
  if ($Yes) {
    return
  }

  $answer = $null

  try {
    $answer = Read-Host "[opm-flow] Remove the items marked 'remove' above? [y/N]"
  }
  catch {
    Die "Cannot ask for confirmation in this kind of window.`n`nRe-run with -Yes to proceed without being asked, or use -DryRun to just preview."
  }

  if ($answer -notmatch '^(y|yes)$') {
    Write-Log "Cancelled. Nothing was changed."
    exit 1
  }
}

#
# ---------------------------------------------------------------------
# Removal
# ---------------------------------------------------------------------
#

function Remove-InstalledFiles {
  foreach ($name in $script:FoundFiles) {
    $path = Join-Path $script:InstallDir $name

    try {
      Remove-Item -LiteralPath $path -Force
      $script:Done.Add("$path")
    }
    catch {
      Write-WarnLog "Could not remove ${path}: $($_.Exception.Message)"
      $script:Left.Add("$path, could not be removed")
      $script:Failures++
    }
  }

  #
  # Folders are only removed if they are empty, never recursively, so
  # anything unexpected that someone put in them is kept, not destroyed.
  #
  if ($script:BinDirExists -and (@(Get-ChildItem -LiteralPath $script:InstallDir -Force).Count -eq 0)) {
    Remove-Item -LiteralPath $script:InstallDir -Force
    $script:Done.Add("$script:InstallDir  (folder)")
  }
  elseif ($script:BinDirExists) {
    $script:Left.Add("$script:InstallDir  (the folder has other files in it, so it was kept)")
  }

  if ($script:ConfigFileExists) {
    try {
      Remove-Item -LiteralPath $script:ConfigFile -Force
      $script:Done.Add("$script:ConfigFile")
    }
    catch {
      Write-WarnLog "Could not remove ${script:ConfigFile}: $($_.Exception.Message)"
      $script:Left.Add("$script:ConfigFile, could not be removed")
      $script:Failures++
    }
  }

  if ($script:ConfigDirExists -and (Test-Path -LiteralPath $script:ConfigDir -PathType Container)) {
    if (@(Get-ChildItem -LiteralPath $script:ConfigDir -Force).Count -eq 0) {
      Remove-Item -LiteralPath $script:ConfigDir -Force
      $script:Done.Add("$script:ConfigDir  (folder)")
    }
    else {
      $script:Left.Add("$script:ConfigDir  (the folder has other files in it, so it was kept)")
    }
  }
}

function Remove-InstallPathEntry {
  if ($null -eq $script:PathPlan) {
    return
  }

  # Save the original first, so a mistake here can always be undone.
  $backup = Join-Path ([IO.Path]::GetTempPath()) ("opmflow-uninstall-user-path-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

  try {
    Set-Content -LiteralPath $backup -Value $script:PathPlan.Raw -Encoding UTF8
    Set-UserPathRaw -Value $script:PathPlan.NewValue
    Send-EnvironmentChange

    foreach ($entry in $script:PathPlan.Removed) {
      $script:Done.Add("PATH entry  ($entry)")
    }

    $script:BackupPath = $backup
  }
  catch {
    Write-WarnLog "Could not update your user PATH: $($_.Exception.Message)"
    $script:Left.Add("PATH entry for $script:InstallDir, could not be removed automatically. Remove it by hand: press the Windows key, search for 'Edit environment variables for your account', open Path, and delete that line.")
    $script:Failures++
    return
  }

  #
  # Also drop it from this window's own PATH so 'flow' stops resolving
  # here right away. Other windows that are already open keep their old
  # copy until they are closed and reopened.
  #
  try {
    $session = Split-PathEntries -PathValue $env:Path -ShouldRemove { param($c) Test-InstallPathEntry $c }
    $env:Path = $session.NewValue
  }
  catch {
    # Cosmetic only. A new window will not have it anyway.
  }
}

#
# Never uses 'docker rmi --force'. If an image is still in use (for
# example a simulation is running right now), Docker refuses, and we
# report that instead of ripping the image out from under a running job.
#
function Remove-Images {
  foreach ($image in $script:Images) {
    $result = Invoke-Docker @("rmi", $image)

    if ($result.ExitCode -eq 0) {
      $script:Done.Add("Docker image $image")
    }
    else {
      Write-WarnLog "Could not remove Docker image ${image}:"
      $result.Output | ForEach-Object { Write-Host "    $_" }
      $script:Left.Add("Docker image $image, Docker refused to remove it (is a simulation still running?)")
      $script:Failures++
    }
  }
}

function Invoke-Uninstall {
  Remove-InstalledFiles
  Remove-InstallPathEntry
  Remove-Images

  foreach ($name in $script:OtherFilesInBin) {
    $script:Left.Add("$(Join-Path $script:InstallDir $name)  (not created by the OPM Flow installer, left alone)")
  }

  if ($script:PathProblem) {
    $script:Left.Add("User PATH, could not be read ($($script:PathProblem)), so nothing there was changed")
  }

  if ($KeepImages) {
    $script:Left.Add("Docker images  (kept because -KeepImages was given)")
  }
  elseif ($script:DockerState -eq "not_running") {
    $script:Left.Add("Docker images  (Docker Desktop was not running, so they could not be checked. Start it, then run this uninstaller again.)")
  }
  elseif ($script:DockerState -eq "missing") {
    $script:Left.Add("Docker images  (Docker was not found, so there was nothing to check)")
  }
}

function Show-Summary {
  Write-Log ""

  if ($script:Done.Count -gt 0) {
    Write-Log "Removed:"
    foreach ($line in $script:Done) {
      Write-Log "    - $line"
    }
    Write-Log ""
  }

  if ($script:Left.Count -gt 0) {
    Write-Log "Left in place:"
    foreach ($line in $script:Left) {
      Write-Log "    - $line"
    }
    Write-Log ""
  }

  if ($script:BackupPath) {
    Write-Log "A backup of your previous PATH was saved to:"
    Write-Log ""
    Write-Log "    $script:BackupPath"
    Write-Log ""
  }

  Write-Log "Docker Desktop, WSL2 and your simulation files were not touched."
  Write-Log ""
  Write-Log "Windows that were already open still remember the old PATH, so"
  Write-Log "'flow' may keep working there until you close and reopen them."

  if ($script:Failures -gt 0) {
    Write-Log ""
    Write-WarnLog "Finished, but $($script:Failures) item(s) could not be removed. See the messages above."
    exit 1
  }

  Write-Log ""
  Write-Log "OPM Flow uninstall completed."
}

function Main {
  if ($Help) {
    Show-Help
    return
  }

  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Die "Could not work out your user folder (LOCALAPPDATA is not set). This script is for Windows."
  }

  Find-Installation

  Show-Plan

  if (Test-NothingToRemove) {
    if (-not $KeepImages -and $script:DockerState -eq "not_running") {
      Write-Log "The OPM Flow commands and settings are already gone, but Docker Desktop"
      Write-Log "is not running, so any downloaded OPM Flow images could not be checked."
      Write-Log "Start Docker Desktop, then run this uninstaller again to clean those up."
    }
    else {
      Write-Log "Nothing to remove. OPM Flow does not appear to be installed."
    }
    return
  }

  if ($DryRun) {
    Write-Log "Dry run: nothing was changed."
    Write-Log "To really uninstall, run the same command without -DryRun."
    return
  }

  Confirm-Proceed
  Invoke-Uninstall
  Show-Summary
}

# Allows this file to be loaded ("dot-sourced") by a test harness
# without running anything. Running the script normally is unaffected.
if ($MyInvocation.InvocationName -ne '.') {
  Main
}
