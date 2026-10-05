#Requires -Version 5.1
<#
.SYNOPSIS
    ResInsight uninstaller for Windows.

.DESCRIPTION
    The counterpart to resinsight-setup.ps1. Removes only what that
    installer put on this computer:

        %LOCALAPPDATA%\ResInsight\<version>      the program (one folder per version)
        ...\<version>.installed-version          its version marker
        Start Menu\Programs\ResInsight.lnk       the Start Menu shortcut
        Desktop\ResInsight.lnk                   the Desktop shortcut (if you asked for one)
        your user PATH                           entries added with -AddToPath
        %LOCALAPPDATA%\resinsight-setup\cache    the download cache

    How it decides what is "ours":

      - A program folder is only removed if the installer's own version
        marker sits next to it and names that same version. A folder
        that merely looks similar is never touched.
      - A shortcut is only removed if it actually points into a version
        being removed. If you have two versions installed and remove
        just one, a shortcut that still points at the other one is left
        working.
      - A PATH entry is only removed if it points into a version being
        removed (or at a folder under the install location that no
        longer exists). Every other entry is kept exactly as it was.

    Your ResInsight project files, and ResInsight's own saved
    preferences, were never created by the installer and are not
    touched. No Administrator rights are needed, and the system-wide PATH
    is never touched.

.PARAMETER Version
    Remove only this version, e.g. '2026.06.1' or 'v2026.06.1'. By
    default every version found is removed.

.PARAMETER InstallRoot
    Where ResInsight was installed. Defaults to
    "$env:LOCALAPPDATA\ResInsight". Use the same value you gave the
    installer, if you gave one.

.PARAMETER KeepCache
    Keep the downloaded installer files, so that a later reinstall does
    not need to download them again.

.PARAMETER DryRun
    Show what would be removed, and change nothing.

.PARAMETER Yes
    Do not ask for confirmation. Useful in scripts.

.EXAMPLE
    .\resinsight-uninstall.ps1 -DryRun

.EXAMPLE
    .\resinsight-uninstall.ps1

.EXAMPLE
    .\resinsight-uninstall.ps1 -Version 2026.06.0

.EXAMPLE
    .\resinsight-uninstall.ps1 -InstallRoot "D:\Tools\ResInsight" -KeepCache
#>

[CmdletBinding()]
param(
  [string]$Version = "",
  [string]$InstallRoot = "$env:LOCALAPPDATA\ResInsight",
  [switch]$KeepCache,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

# [IO.Path]::Combine (unlike Join-Path) does not throw a raw error if
# LOCALAPPDATA is somehow unset, so Main can give a friendly message.
$script:CacheParent = [IO.Path]::Combine("$env:LOCALAPPDATA", "resinsight-setup")
$script:CacheDir = [IO.Path]::Combine($script:CacheParent, "cache")
$script:DefaultInstallRoot = [IO.Path]::Combine("$env:LOCALAPPDATA", "ResInsight")
$script:StartMenuLink = [IO.Path]::Combine("$env:APPDATA", "Microsoft", "Windows", "Start Menu", "Programs", "ResInsight.lnk")

$script:OnlyTag = ""

# What Find-Installation fills in.
$script:Installs = @()          # objects with Tag, Target, Marker
$script:StrayMarkers = @()      # markers whose program folder is already gone
$script:ForeignNotes = @()      # things that look related but are not ours (kept)
$script:Shortcuts = @()         # objects with Path, Label, Decision, Detail
$script:PathPlan = $null
$script:PathProblem = $null
$script:CacheDirs = @()
$script:BackupPath = $null

$script:Done = New-Object System.Collections.Generic.List[string]
$script:Left = New-Object System.Collections.Generic.List[string]
$script:Failures = 0

function Write-Log {
  param([string]$Message)
  Write-Host "[resinsight] $Message"
}

function Write-WarningLog {
  param([string]$Message)
  Write-Host "[resinsight] warning: $Message" -ForegroundColor Yellow
}

function Die {
  param([string]$Message)
  Write-Host "[resinsight] error: $Message" -ForegroundColor Red
  exit 1
}

function Write-Plan {
  param([string]$Action, [string]$Text)
  Write-Log ("    {0,-9} {1}" -f $Action, $Text)
}

function Show-Help {
  @"
ResInsight uninstaller (Windows)

Removes what resinsight-setup.ps1 installed: the program, its Start Menu
and Desktop shortcuts, any PATH entry added with -AddToPath, and the
download cache. It does not touch your ResInsight project files or
ResInsight's own saved preferences.

No Administrator rights are needed.

Usage:

    .\resinsight-uninstall.ps1 [options]

Options:

    -DryRun              Show what would be removed, and change nothing.
    -Version VERSION     Remove only this version, e.g. '2026.06.1' or
                         'v2026.06.1'. By default every version found is
                         removed.
    -InstallRoot DIR     Where ResInsight was installed (default:
                         $script:DefaultInstallRoot). Use the same value you
                         gave the installer, if you gave one.
    -KeepCache           Keep the downloaded installer files, so that a
                         later reinstall does not need to download them
                         again.
    -Yes                 Do not ask for confirmation. Useful in scripts.
    -Help                Show this help and exit

Examples:

    .\resinsight-uninstall.ps1 -DryRun
    .\resinsight-uninstall.ps1
    .\resinsight-uninstall.ps1 -Version 2026.06.0
    .\resinsight-uninstall.ps1 -InstallRoot "D:\Tools\ResInsight"
    .\resinsight-uninstall.ps1 -KeepCache -Yes
"@
}

#
# A version tag becomes part of a folder path that gets deleted, so it
# is validated strictly: only letters, digits, dots, dashes and
# underscores, must start with a letter or digit, and no '..'. That
# rules out anything containing a slash or that could climb out of the
# install folder.
#
function Test-ValidTag {
  param([string]$Tag)

  return ($Tag -match '^[A-Za-z0-9][A-Za-z0-9._-]*$') -and ($Tag -notlike '*..*')
}

#
# ---------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------
#

# Only used to COMPARE paths. Anything that is kept is left exactly as
# it was found.
function Expand-PathText {
  param([string]$PathText)

  if ([string]::IsNullOrWhiteSpace($PathText)) {
    return ""
  }

  $expanded = [Environment]::ExpandEnvironmentVariables($PathText.Trim().Trim('"'))

  return $expanded.Replace('/', '\').TrimEnd('\')
}

function ConvertTo-ComparablePath {
  param([string]$PathText)

  return (Expand-PathText $PathText).ToLowerInvariant()
}

# True if path $Path is the same as, or inside, folder $Dir.
function Test-PathWithin {
  param([string]$Path, [string]$Dir)

  $p = ConvertTo-ComparablePath $Path
  $d = ConvertTo-ComparablePath $Dir

  if ($d -eq "") {
    return $false
  }

  return ($p -eq $d) -or $p.StartsWith($d + '\')
}

function Test-IsReparsePoint {
  param([string]$Path)

  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue

  if ($null -eq $item) {
    return $false
  }

  return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-FolderSize {
  param([string]$Path)

  $bytes = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
      Measure-Object -Property Length -Sum).Sum

  if ($null -eq $bytes) {
    $bytes = 0
  }

  if ($bytes -ge 1GB) {
    return ("{0:N1} GB" -f ($bytes / 1GB))
  }

  return ("{0:N0} MB" -f ($bytes / 1MB))
}

#
# Never treat a drive root, or one of the main per-user folders, as an
# install location. Nothing here is ever deleted wholesale from the
# install root, but the "stale PATH entry" and "tidy up an empty
# folder" rules look at it, and those must not apply to something as
# broad as C:\ or the whole user profile.
#
function Test-UnsafeRoot {
  param([string]$Root)

  if ([string]::IsNullOrWhiteSpace($Root)) {
    return $true
  }

  $full = [IO.Path]::GetFullPath($Root)

  # A drive root such as C:\ (checked before any trimming, because
  # "C:" on its own would mean "the current folder on drive C").
  if ($full -eq [IO.Path]::GetPathRoot($full)) {
    return $true
  }

  $trimmed = ConvertTo-ComparablePath $full

  foreach ($broad in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, $env:SystemRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($broad) -and ($trimmed -eq (ConvertTo-ComparablePath $broad))) {
      return $true
    }
  }

  return $false
}

#
# ---------------------------------------------------------------------
# PATH handling
#
# Windows keeps the user PATH in the registry, and the value can be a
# plain string or an "expandable" string that contains %VARIABLES%.
# The convenient .NET calls GetEnvironmentVariable/SetEnvironmentVariable
# quietly expand those variables into fixed text and rewrite the value
# as a plain string, so a round trip through them subtly changes
# entries that have nothing to do with this uninstaller. To avoid that,
# the raw value is read with expansion switched off, edited as plain
# text, and written back with its original type.
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
    $name = "RESINSIGHT_UNINSTALL_NOTIFY"
    [Environment]::SetEnvironmentVariable($name, "1", "User")
    [Environment]::SetEnvironmentVariable($name, $null, "User")
  }
  catch {
    Write-WarningLog "Could not notify Windows about the PATH change. Sign out and back in, or open a new terminal, for it to take effect."
  }
}

function Split-PathEntries {
  param([string]$PathValue, [scriptblock]$ShouldRemove)

  $kept = New-Object System.Collections.Generic.List[string]
  $removed = New-Object System.Collections.Generic.List[string]

  foreach ($entry in $PathValue.Split(';')) {
    $expanded = Expand-PathText $entry

    if ($expanded -ne "" -and (& $ShouldRemove $expanded)) {
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

#
# A PATH entry is ours to remove if it points into a version being
# removed, or if it points at something under the install root that no
# longer exists (a leftover from an earlier version: the installer's
# -AddToPath never cleaned up after itself when a newer version was
# installed). Existence is checked on the real, un-lowercased path.
#
function Test-OurPathEntry {
  param([string]$Expanded)

  foreach ($install in $script:Installs) {
    if (Test-PathWithin $Expanded $install.Target) {
      return $true
    }
  }

  # Stale-entry cleanup only happens when removing everything. If one
  # specific -Version was asked for, nothing else is touched.
  if ($script:OnlyTag -eq "" -and (Test-PathWithin $Expanded $InstallRoot) -and -not (Test-Path -LiteralPath $Expanded)) {
    return $true
  }

  return $false
}

function Get-UserPathPlan {
  $raw = Get-UserPathRaw

  if ([string]::IsNullOrEmpty($raw)) {
    return $null
  }

  $result = Split-PathEntries -PathValue $raw -ShouldRemove { param($e) Test-OurPathEntry $e }

  if ($result.Removed.Count -eq 0) {
    return $null
  }

  return [pscustomobject]@{
    Raw      = $raw
    NewValue = $result.NewValue
    Removed  = $result.Removed
  }
}

#
# ---------------------------------------------------------------------
# Shortcuts
# ---------------------------------------------------------------------
#

function Get-DesktopDir {
  return [Environment]::GetFolderPath("Desktop")
}

# Reads where a .lnk file points, using the standard Windows shortcut
# object. Returns $null if it cannot be read, in which case the
# shortcut is left alone.
function Get-ShortcutTarget {
  param([string]$Path)

  $shell = $null

  try {
    $shell = New-Object -ComObject WScript.Shell
    return [string]$shell.CreateShortcut($Path).TargetPath
  }
  catch {
    return $null
  }
  finally {
    if ($null -ne $shell) {
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
  }
}

#
# Decides what to do with one shortcut. It is removed when it points
# into a version being removed, or (only when removing everything) at a
# missing file under the install root (a dead shortcut). If it points anywhere else (another version
# we are keeping, or a different install location altogether) it is
# kept, so removing one version never breaks another.
#
function Get-ShortcutDecision {
  param([string]$Path, [string]$Label)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }

  $target = Get-ShortcutTarget $Path

  if ([string]::IsNullOrWhiteSpace($target)) {
    return [pscustomobject]@{ Path = $Path; Label = $Label; Decision = "unreadable"; Detail = "" }
  }

  foreach ($install in $script:Installs) {
    if (Test-PathWithin $target $install.Target) {
      return [pscustomobject]@{ Path = $Path; Label = $Label; Decision = "remove"; Detail = $target }
    }
  }

  if ($script:OnlyTag -eq "" -and (Test-PathWithin $target $InstallRoot) -and -not (Test-Path -LiteralPath $target)) {
    return [pscustomobject]@{ Path = $Path; Label = $Label; Decision = "remove"; Detail = $target }
  }

  return [pscustomobject]@{ Path = $Path; Label = $Label; Decision = "keep"; Detail = $target }
}

#
# ---------------------------------------------------------------------
# Inspect, plan, confirm
# ---------------------------------------------------------------------
#

#
# Looks for every version this installer put under the install root. A
# version counts only if its marker file exists and names the same
# version as the folder it sits next to.
#
function Find-Installs {
  if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
    return
  }

  $markers = @(Get-ChildItem -LiteralPath $InstallRoot -File -Force |
      Where-Object { $_.Name.EndsWith(".installed-version") })

  foreach ($marker in $markers) {
    $name = $marker.Name.Substring(0, $marker.Name.Length - ".installed-version".Length)
    $tag = ""

    try {
      $tag = (Get-Content -LiteralPath $marker.FullName -Raw).Trim()
    }
    catch {
      continue
    }

    if ($tag -ne $name -or -not (Test-ValidTag $tag)) {
      continue
    }

    if ($script:OnlyTag -ne "" -and $tag -ne $script:OnlyTag) {
      continue
    }

    $target = Join-Path $InstallRoot $name

    if (Test-IsReparsePoint $target) {
      $script:ForeignNotes += "$target  (a link, not a folder the installer made, left alone)"
    }
    elseif (Test-Path -LiteralPath $target -PathType Container) {
      $script:Installs += [pscustomobject]@{ Tag = $tag; Target = $target; Marker = $marker.FullName }
    }
    elseif (-not (Test-Path -LiteralPath $target)) {
      $script:StrayMarkers += $marker.FullName
    }
  }
}

function Find-Installation {
  Find-Installs

  $startMenu = Get-ShortcutDecision -Path $script:StartMenuLink -Label "Start Menu shortcut"
  if ($startMenu) {
    $script:Shortcuts += $startMenu
  }

  $desktopDir = Get-DesktopDir
  if (-not [string]::IsNullOrWhiteSpace($desktopDir)) {
    $desktop = Get-ShortcutDecision -Path (Join-Path $desktopDir "ResInsight.lnk") -Label "Desktop shortcut"
    if ($desktop) {
      $script:Shortcuts += $desktop
    }
  }

  try {
    $script:PathPlan = Get-UserPathPlan
  }
  catch {
    $script:PathProblem = $_.Exception.Message
  }

  if (-not $KeepCache -and (Test-Path -LiteralPath $script:CacheDir -PathType Container)) {
    if ($script:OnlyTag -ne "") {
      $one = Join-Path $script:CacheDir $script:OnlyTag
      if ((Test-Path -LiteralPath $one -PathType Container) -and -not (Test-IsReparsePoint $one)) {
        $script:CacheDirs += $one
      }
    }
    else {
      foreach ($dir in @(Get-ChildItem -LiteralPath $script:CacheDir -Directory -Force)) {
        if ((Test-ValidTag $dir.Name) -and -not (Test-IsReparsePoint $dir.FullName)) {
          $script:CacheDirs += $dir.FullName
        }
      }
    }
  }
}

function Test-NothingToRemove {
  return ($script:Installs.Count -eq 0) -and
  ($script:StrayMarkers.Count -eq 0) -and
  (@($script:Shortcuts | Where-Object { $_.Decision -eq "remove" }).Count -eq 0) -and
  ($null -eq $script:PathPlan) -and
  ($script:CacheDirs.Count -eq 0)
}

function Show-Plan {
  Write-Log "ResInsight uninstaller"
  Write-Log ""
  Write-Log "Looking in: $InstallRoot"
  Write-Log ""
  Write-Log "Found on this computer:"
  Write-Log ""

  foreach ($install in $script:Installs) {
    Write-Plan "remove" "$($install.Target)   (ResInsight $($install.Tag), $(Get-FolderSize $install.Target))"
  }

  foreach ($marker in $script:StrayMarkers) {
    Write-Plan "remove" "$marker   (leftover version marker)"
  }

  foreach ($shortcut in $script:Shortcuts) {
    switch ($shortcut.Decision) {
      "remove" { Write-Plan "remove" "$($shortcut.Path)   ($($shortcut.Label))" }
      "keep" { Write-Plan "keep" "$($shortcut.Path)   ($($shortcut.Label); it points at $($shortcut.Detail), which is not being removed)" }
      "unreadable" { Write-Plan "keep" "$($shortcut.Path)   ($($shortcut.Label); could not be read, so it was left alone)" }
    }
  }

  if ($script:PathPlan) {
    foreach ($entry in $script:PathPlan.Removed) {
      Write-Plan "remove" "$entry   (entry in your user PATH; a backup is saved first)"
    }
  }

  if ($script:PathProblem) {
    Write-Plan "skip" "user PATH   (could not be read: $($script:PathProblem))"
  }

  foreach ($dir in $script:CacheDirs) {
    Write-Plan "remove" "$dir   (downloaded installer files, $(Get-FolderSize $dir))"
  }

  if ($KeepCache) {
    Write-Plan "keep" "downloaded installer files   (because -KeepCache was given)"
  }

  foreach ($note in $script:ForeignNotes) {
    Write-Plan "keep" $note
  }

  Write-Log ""
  Write-Log "Not touched, on purpose:"
  Write-Log "    - your ResInsight project files"
  Write-Log "    - ResInsight's own saved preferences"
  Write-Log ""
}

#
# The installer does not record where it installed to. If a shortcut
# points at ResInsight somewhere other than the folder we searched,
# that is the most likely reason nothing was found, so say where to
# look instead of just giving up.
#
function Show-OtherLocationHint {
  $elsewhere = @($script:Shortcuts | Where-Object { $_.Decision -eq "keep" -and $_.Detail -match 'ResInsight' } | Select-Object -First 1)

  if ($elsewhere.Count -eq 0) {
    return
  }

  Write-Log ""
  Write-Log "However, your $($elsewhere[0].Label.ToLower()) points at:"
  Write-Log ""
  Write-Log "    $($elsewhere[0].Detail)"
  Write-Log ""
  Write-Log "so ResInsight may be installed somewhere other than $InstallRoot."
  Write-Log "If you gave the installer a custom -InstallRoot, give the same one"
  Write-Log "here, for example:"
  Write-Log ""
  Write-Log "    .\resinsight-uninstall.ps1 -InstallRoot ""D:\that\folder"""
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
    $answer = Read-Host "[resinsight] Remove the items marked 'remove' above? [y/N]"
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
# Windows will not delete files that are in use, and removing a
# program folder half-way through is worse than not starting. So if
# ResInsight is running from a folder about to be removed, ask for it
# to be closed first. A running copy whose location cannot be read is
# treated as a match, to stay on the safe side.
#
function Test-ResInsightRunning {
  if ($script:Installs.Count -eq 0) {
    return $false
  }

  foreach ($process in @(Get-Process -Name "ResInsight" -ErrorAction SilentlyContinue)) {
    $location = $null

    try {
      $location = $process.Path
    }
    catch {
      return $true
    }

    if ([string]::IsNullOrWhiteSpace($location)) {
      return $true
    }

    foreach ($install in $script:Installs) {
      if (Test-PathWithin $location $install.Target) {
        return $true
      }
    }
  }

  return $false
}

#
# ---------------------------------------------------------------------
# Removal
# ---------------------------------------------------------------------
#

function Remove-Installs {
  foreach ($install in $script:Installs) {
    #
    # The marker is removed only after the folder is gone. If the
    # folder cannot be fully removed (for example something has a file
    # open), the marker stays, so running the uninstaller again still
    # recognises this as ours and retries.
    #
    try {
      if (Test-IsReparsePoint $install.Target) {
        throw "it is a link, not a normal folder"
      }

      Remove-Item -LiteralPath $install.Target -Recurse -Force
      Remove-Item -LiteralPath $install.Marker -Force
      $script:Done.Add("ResInsight $($install.Tag)  ($($install.Target))")
    }
    catch {
      Write-WarningLog "Could not fully remove $($install.Target): $($_.Exception.Message)"
      $script:Left.Add("ResInsight $($install.Tag)  ($($install.Target)), could not be fully removed. Close ResInsight and any File Explorer window showing that folder, then run this again.")
      $script:Failures++
    }
  }

  foreach ($marker in $script:StrayMarkers) {
    try {
      Remove-Item -LiteralPath $marker -Force
      $script:Done.Add("Leftover version marker  ($marker)")
    }
    catch {
      $script:Left.Add("$marker, could not be removed")
      $script:Failures++
    }
  }

  #
  # Tidy up the install folder itself only when it is the default one
  # this installer creates and it is now empty. A folder you chose
  # yourself with -InstallRoot is yours, so it is left in place even
  # when empty. Remove-Item without -Recurse on a folder that still has
  # files in it would prompt, so emptiness is checked first.
  #
  if ((ConvertTo-ComparablePath $InstallRoot) -eq (ConvertTo-ComparablePath $script:DefaultInstallRoot) -and
    (Test-Path -LiteralPath $InstallRoot -PathType Container) -and
    (@(Get-ChildItem -LiteralPath $InstallRoot -Force).Count -eq 0)) {
    Remove-Item -LiteralPath $InstallRoot -Force
  }
}

function Remove-Shortcuts {
  foreach ($shortcut in $script:Shortcuts) {
    switch ($shortcut.Decision) {
      "remove" {
        try {
          Remove-Item -LiteralPath $shortcut.Path -Force
          $script:Done.Add("$($shortcut.Label)  ($($shortcut.Path))")
        }
        catch {
          Write-WarningLog "Could not remove $($shortcut.Path): $($_.Exception.Message)"
          $script:Left.Add("$($shortcut.Label)  ($($shortcut.Path)), could not be removed")
          $script:Failures++
        }
      }
      "keep" {
        $script:Left.Add("$($shortcut.Label)  ($($shortcut.Path)), it points at $($shortcut.Detail), which is not being removed")
      }
      "unreadable" {
        $script:Left.Add("$($shortcut.Label)  ($($shortcut.Path)), could not be read, so it was left alone")
      }
    }
  }
}

function Remove-PathEntries {
  if ($null -eq $script:PathPlan) {
    return
  }

  # Save the original first, so a mistake here can always be undone.
  $backup = Join-Path ([IO.Path]::GetTempPath()) ("resinsight-uninstall-user-path-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

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
    Write-WarningLog "Could not update your user PATH: $($_.Exception.Message)"
    $script:Left.Add("PATH entries for ResInsight, could not be removed automatically. Remove them by hand: press the Windows key, search for 'Edit environment variables for your account', open Path, and delete the lines that point into ResInsight.")
    $script:Failures++
    return
  }

  # Also drop them from this window's own PATH. Other windows that are
  # already open keep their old copy until they are closed and reopened.
  try {
    $session = Split-PathEntries -PathValue $env:Path -ShouldRemove { param($e) Test-OurPathEntry $e }
    $env:Path = $session.NewValue
  }
  catch {
    # Cosmetic only. A new window will not have it anyway.
  }
}

function Remove-Cache {
  foreach ($dir in $script:CacheDirs) {
    try {
      Remove-Item -LiteralPath $dir -Recurse -Force
      $script:Done.Add("Downloaded installer files  ($dir)")
    }
    catch {
      Write-WarningLog "Could not remove ${dir}: $($_.Exception.Message)"
      $script:Left.Add("$dir, could not be removed")
      $script:Failures++
    }
  }

  #
  # Remove the cache folders themselves only if they are now empty, so
  # that anything unexpected someone left in them is never destroyed.
  #
  foreach ($folder in @($script:CacheDir, $script:CacheParent)) {
    if ((Test-Path -LiteralPath $folder -PathType Container) -and (@(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0)) {
      Remove-Item -LiteralPath $folder -Force
    }
  }
}

function Invoke-Uninstall {
  Remove-Installs
  Remove-Shortcuts
  Remove-PathEntries
  Remove-Cache

  foreach ($note in $script:ForeignNotes) {
    $script:Left.Add($note)
  }

  if ($script:PathProblem) {
    $script:Left.Add("User PATH, could not be read ($($script:PathProblem)), so nothing there was changed")
  }

  if ($KeepCache) {
    $script:Left.Add("Downloaded installer files  (kept because -KeepCache was given)")
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

  #
  # If a shortcut was removed because it pointed at the version just
  # removed, but another version is still installed, that version has
  # no shortcut any more. Say so plainly, with the exact fix.
  #
  if ($script:OnlyTag -ne "" -and @($script:Shortcuts | Where-Object { $_.Decision -eq "remove" }).Count -gt 0) {
    Write-Log "Note: a shortcut pointed at the version you removed. If you have another"
    Write-Log "version installed and want the shortcut back for it, run the installer"
    Write-Log "again for that version, for example:"
    Write-Log ""
    Write-Log "    .\resinsight-setup.ps1 -Version <that version>"
    Write-Log ""
  }

  Write-Log "Your project files and ResInsight's own preferences were not touched."
  Write-Log ""
  Write-Log "Windows that were already open still remember the old PATH, so"
  Write-Log "'resinsight' may keep working there until you close and reopen them."

  if ($script:Failures -gt 0) {
    Write-Log ""
    Write-WarningLog "Finished, but $($script:Failures) item(s) could not be removed. See the messages above."
    exit 1
  }

  Write-Log ""
  Write-Log "ResInsight uninstall completed."
}

function Main {
  if ($Help) {
    Show-Help
    return
  }

  if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Die "Could not work out your user folder (LOCALAPPDATA is not set). This script is for Windows."
  }

  if ($Version -ne "") {
    # People type the version as it appears on the releases page
    # ('2026.06.1'); the installer's folders and markers use the git
    # tag ('v2026.06.1'). Accept either.
    $script:OnlyTag = $Version
    if (-not $script:OnlyTag.StartsWith("v")) {
      $script:OnlyTag = "v$($script:OnlyTag)"
    }

    if (-not (Test-ValidTag $script:OnlyTag)) {
      Die "Invalid version: $Version`n`nExpected something like: 2026.06.1"
    }
  }

  # Resolve a relative -InstallRoot using PowerShell's current folder.
  # (.NET's own idea of "current folder" can differ from it.)
  if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
    $script:InstallRoot = (Resolve-Path -LiteralPath $InstallRoot).ProviderPath
  }

  if (Test-UnsafeRoot $InstallRoot) {
    Die "Refusing to use '$InstallRoot' as the install folder, it is too broad.`n`nGive the folder ResInsight itself was installed into."
  }

  Find-Installation

  Show-Plan

  if (Test-NothingToRemove) {
    if ($script:OnlyTag -ne "") {
      Write-Log "Version $Version was not found under $InstallRoot."
      Write-Log "Run without -Version to see everything that is installed there."
    }
    else {
      Write-Log "Nothing to remove under $InstallRoot."
      Show-OtherLocationHint
    }
    return
  }

  if ($script:Installs.Count -eq 0 -and $script:OnlyTag -eq "") {
    Write-Log "No ResInsight program folder was found under $InstallRoot."
    Show-OtherLocationHint
  }

  if (Test-ResInsightRunning) {
    if ($DryRun) {
      Write-WarningLog "ResInsight is running right now. Close it before the real uninstall."
    }
    else {
      Die "ResInsight is running right now.`n`nClose it completely, then run this uninstaller again."
    }
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
