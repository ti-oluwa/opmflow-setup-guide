# Requires -Version 5.1
<#
.SYNOPSIS
    ResInsight installer for Windows.

.DESCRIPTION
    Downloads and installs a ResInsight release from
    https://github.com/OPM/ResInsight/releases

    ResInsight's Windows release asset has changed names across
    versions, so this script never guesses a filename: it always asks
    the GitHub API for the real list of assets attached to the chosen
    release, then picks the one that looks like a Windows build. If
    that release genuinely has no Windows asset, it says so rather
    than downloading the wrong thing.

    Once a version is installed, re-running this script is a no-op
    unless the release changes or -Force is passed, it will not
    redownload or reinstall the same version.

    Downloaded archives are also cached on disk (by release + asset
    name) under "$env:LOCALAPPDATA\resinsight-setup\cache", so even
    -Force or a different -InstallRoot reuses the already-downloaded
    file instead of fetching it from GitHub again, as long as its size
    still matches what GitHub reports for that asset.

.PARAMETER Version
    Release to install, e.g. '2026.06.1' or 'v2026.06.1'. Defaults to
    the latest published release.

.PARAMETER InstallRoot
    Where to install. Defaults to
    "$env:LOCALAPPDATA\ResInsight".

.PARAMETER AddToPath
    If set, prepends the installed version's folder to the current
    user's PATH environment variable.

.PARAMETER Force
    Reinstall even if this version is already installed.

.PARAMETER NoCache
    Always download fresh; don't read from or write to the download
    cache.

.EXAMPLE
    .\resinsight-setup.ps1

.EXAMPLE
    .\resinsight-setup.ps1 -Version 2026.06.1

.EXAMPLE
    .\resinsight-setup.ps1 -Version 2025.09.3 -AddToPath

.EXAMPLE
    .\resinsight-setup.ps1 -Force

.EXAMPLE
    .\resinsight-setup.ps1 -Force -NoCache
#>

[CmdletBinding()]
param(
  [string]$Version = "latest",
  [string]$InstallRoot = "$env:LOCALAPPDATA\ResInsight",
  [switch]$AddToPath,
  [switch]$Force,
  [switch]$NoCache,
  [switch]$NoShortcut,
  [switch]$DesktopShortcut
)

$ErrorActionPreference = "Stop"

$Repo = "OPM/ResInsight"
$ApiBase = "https://api.github.com/repos/$Repo"
$CacheDir = "$env:LOCALAPPDATA\resinsight-setup\cache"

function Write-Log {
  param([string]$Message)
  Write-Host "[resinsight] $Message"
}

function Write-WarningLog {
  param([string]$Message)
  Write-Warning "[resinsight] $Message"
}

function Die {
  param([string]$Message)
  Write-Host "[resinsight] error: $Message" -ForegroundColor Red
  exit 1
}

function Get-ReleaseJson {
  param([string]$RequestedVersion)

  if ($RequestedVersion -eq "latest") {
    $url = "$ApiBase/releases/latest"
  }
  else {
    # Accept the version with or without a leading 'v'. The repo's
    # tags are all 'vYYYY.MM.P', but people naturally type the
    # version as shown on the releases page (e.g. '2026.06.1').
    $tag = $RequestedVersion
    if (-not $tag.StartsWith("v")) {
      $tag = "v$tag"
    }
    $url = "$ApiBase/releases/tags/$tag"
  }

  try {
    $headers = @{
      "Accept"     = "application/vnd.github+json"
      "User-Agent" = "resinsight-setup.ps1"
    }
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
  }
  catch {
    $statusCode = $null
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }

    if ($statusCode -eq 404) {
      Die "No ResInsight release found for version '$RequestedVersion'.`n`nCheck https://github.com/$Repo/releases for valid version tags."
    }
    elseif ($statusCode -eq 403) {
      Die "GitHub API rate limit likely exceeded (unauthenticated requests are limited per IP). Wait a while and try again."
    }
    else {
      Die "Unable to reach the GitHub API at:`n`n    $url`n`n$($_.Exception.Message)"
    }
  }
}

# Cache path for a given release's asset, namespaced by tag, not just
# by asset name, in case a future release ever reuses a static
# filename from an older one (already true today for at least one
# asset on the Linux side of this project).
function Get-CachePath {
  param([string]$Tag, [string]$AssetName)
  return Join-Path (Join-Path $CacheDir $Tag) $AssetName
}

# Returns the cached file's path if a valid copy already exists
# (present, and its size matches what GitHub reports for the asset).
# A size mismatch is treated as a corrupt/partial leftover from an
# interrupted download, not a valid cache hit, and is removed.
function Resolve-CachedArchive {
  param([string]$Tag, [string]$AssetName, [long]$ExpectedSize)

  if ($NoCache) {
    return $null
  }

  $cached = Get-CachePath -Tag $Tag -AssetName $AssetName
  if (-not (Test-Path $cached)) {
    return $null
  }

  $actualSize = (Get-Item $cached).Length
  if ($actualSize -ne $ExpectedSize) {
    Write-WarningLog "Cached archive size mismatch (expected $ExpectedSize bytes, found $actualSize); ignoring and re-downloading."
    Remove-Item -Force $cached
    return $null
  }

  return $cached
}

function Select-WindowsAsset {
  param($Release)

  $patterns = @('win(64|32)?', 'windows')

  foreach ($pattern in $patterns) {
    $match = $Release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if ($match) {
      return $match
    }
  }

  $available = ($Release.assets | ForEach-Object { "    $($_.name)" }) -join "`n"
  if (-not $available) {
    $available = "    (none)"
  }

  Die @"
Release $($Release.tag_name) has no Windows asset.

Assets actually published in this release:

$available

Try a different -Version, or check https://github.com/$Repo/releases yourself.
"@
}

function Expand-ReleaseArchive {
  param(
    [string]$ArchivePath,
    [string]$DestDir
  )

  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

  if ($ArchivePath -like "*.zip") {
    Expand-Archive -Path $ArchivePath -DestinationPath $DestDir -Force
  }
  elseif ($ArchivePath -like "*.tar.gz" -or $ArchivePath -like "*.tgz") {
    # tar has shipped built into Windows since 10 (1803) / Windows 11.
    tar -xzf $ArchivePath -C $DestDir
    if ($LASTEXITCODE -ne 0) {
      Die "Failed to extract: $ArchivePath"
    }
  }
  else {
    Die "Don't know how to extract: $ArchivePath (expected .zip or .tar.gz)"
  }
}

# If extraction produced exactly one directory at the top level, treat
# that as the real install root so we don't end up with a redundant
# extra directory level.
function Resolve-SingleSubdir {
  param([string]$DestDir)

  $entries = Get-ChildItem -Path $DestDir
  if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
    return $entries[0].FullName
  }
  return $DestDir
}

# A zip's top-level layout varies (sometimes one wrapping directory,
# sometimes the files directly, and sometimes, as confirmed on the
# Linux/RHEL8 asset, a single nested archive that itself needs
# extracting before there's anything to find). This loops flattening a
# lone wrapping directory and unwrapping a lone nested archive file,
# in whatever order/combination they show up, until neither applies.
# Capped so a pathological or unexpected archive can't loop forever.
function Resolve-NormalizedExtractDir {
  param([string]$DestDir, [int]$MaxIterations = 5)

  for ($i = 0; $i -lt $MaxIterations; $i++) {
    $DestDir = Resolve-SingleSubdir -DestDir $DestDir

    $entries = Get-ChildItem -Path $DestDir
    if ($entries.Count -eq 1 -and -not $entries[0].PSIsContainer -and
      ($entries[0].Name -like "*.zip" -or $entries[0].Name -like "*.tar.gz" -or $entries[0].Name -like "*.tgz")) {

      $nested = $entries[0].FullName
      Write-Log "Found a nested archive inside the download, extracting: $($entries[0].Name)"

      $innerDest = Join-Path (Split-Path $DestDir -Parent) ("unwrapped-" + [guid]::NewGuid().ToString("N"))
      Expand-ReleaseArchive -ArchivePath $nested -DestDir $innerDest
      Remove-Item -Force $nested

      Get-ChildItem -Path $innerDest | Move-Item -Destination $DestDir
      Remove-Item -Recurse -Force $innerDest

      continue
    }

    return $DestDir
  }

  Write-WarningLog "Archive nesting went $MaxIterations levels deep without bottoming out; proceeding with what's there."
  return $DestDir
}

# Version marker file, so a re-run can tell whether the requested
# release is already installed without redownloading anything to
# check. Kept as a plain sibling file next to the versioned install
# folder rather than something inside it, so it can never be mistaken
# for part of the actual ResInsight install.
function Get-VersionMarkerPath {
  param([string]$Target)
  return "$Target.installed-version"
}

function Test-AlreadyInstalled {
  param([string]$Target, [string]$Tag)

  if (-not (Test-Path $Target)) {
    return $false
  }

  $marker = Get-VersionMarkerPath -Target $Target
  if (-not (Test-Path $marker)) {
    return $false
  }

  $installedTag = (Get-Content $marker -Raw).Trim()
  if ($installedTag -ne $Tag) {
    return $false
  }

  # Guard against a marker left behind by an interrupted install:
  # confirm the executable is actually there too before trusting it.
  $exe = Get-ChildItem -Path $Target -Recurse -Filter "ResInsight.exe" -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  return [bool]$exe
}

# Creates a Start Menu shortcut (and optionally a Desktop one) via the
# WScript.Shell COM object as this is the standard way to make a .lnk file from
# PowerShell without any extra module. Both locations used here are
# per-user ($env:APPDATA / the current user's Desktop folder), so this
# needs no elevation, consistent with the rest of this installer.
function New-AppShortcut {
  param([string]$ExePath)

  $shell = New-Object -ComObject WScript.Shell

  $startMenuDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
  New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null

  $startMenuLink = Join-Path $startMenuDir "ResInsight.lnk"
  $shortcut = $shell.CreateShortcut($startMenuLink)
  $shortcut.TargetPath = $ExePath
  $shortcut.WorkingDirectory = Split-Path $ExePath -Parent
  $shortcut.IconLocation = $ExePath
  $shortcut.Save()
  Write-Log "Start Menu shortcut created: $startMenuLink"

  if ($DesktopShortcut) {
    $desktopDir = [Environment]::GetFolderPath("Desktop")
    $desktopLink = Join-Path $desktopDir "ResInsight.lnk"
    $shortcut2 = $shell.CreateShortcut($desktopLink)
    $shortcut2.TargetPath = $ExePath
    $shortcut2.WorkingDirectory = Split-Path $ExePath -Parent
    $shortcut2.IconLocation = $ExePath
    $shortcut2.Save()
    Write-Log "Desktop shortcut created: $desktopLink"
  }
}

function Install-ResInsight {
  param(
    [string]$ExtractedDir,
    [string]$Tag
  )

  $target = Join-Path $InstallRoot $Tag

  if (Test-Path $target) {
    Write-WarningLog "Removing existing install at $target"
    Remove-Item -Recurse -Force $target
  }

  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
  Move-Item -Path $ExtractedDir -Destination $target

  $exe = Get-ChildItem -Path $target -Recurse -Filter "ResInsight.exe" -Depth 2 | Select-Object -First 1

  if (-not $exe) {
    Die "Could not find ResInsight.exe inside:`n`n    $target`n`nExtraction may have produced an unexpected layout - inspect it manually."
  }

  Set-Content -Path (Get-VersionMarkerPath -Target $target) -Value $Tag -Encoding UTF8

  Write-Log "Installed to $target"
  Write-Log "Executable: $($exe.FullName)"

  if (-not $NoShortcut) {
    try {
      New-AppShortcut -ExePath $exe.FullName
    }
    catch {
      Write-WarningLog "Could not create a shortcut: $($_.Exception.Message)"
    }
  }

  if ($AddToPath) {
    $exeDir = $exe.DirectoryName
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($currentPath -notlike "*$exeDir*") {
      $newPath = "$exeDir;$currentPath"
      [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
      Write-Log "Added to user PATH: $exeDir"
      Write-Log "Restart your terminal for PATH changes to take effect."
    }
    else {
      Write-Log "Already on PATH: $exeDir"
    }
  }
  else {
    Write-Log "Run it with: & '$($exe.FullName)'"
    Write-Log "(Pass -AddToPath to add it to your PATH instead.)"
  }
}

function Main {
  Write-Log "Resolving ResInsight release: $Version"

  # The release JSON call is a small metadata request, not a
  # download. It's always made so 'latest' resolves to a real tag,
  # even when the resolved version turns out to already be
  # installed and nothing further needs to happen.
  $release = Get-ReleaseJson -RequestedVersion $Version
  $tag = $release.tag_name

  Write-Log "Resolved to release: $tag"

  $target = Join-Path $InstallRoot $tag

  if (-not $Force -and (Test-AlreadyInstalled -Target $target -Tag $tag)) {
    Write-Log "$tag is already installed at $target - nothing to do."
    Write-Log "Re-run with -Force to reinstall anyway."
    return
  }

  if (-not $release.assets -or $release.assets.Count -eq 0) {
    Die "Release $tag has no downloadable assets at all."
  }

  $asset = Select-WindowsAsset -Release $release
  Write-Log "Selected asset: $($asset.name)"

  $workDir = Join-Path $env:TEMP ("resinsight-setup-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $workDir | Out-Null

  try {
    $cachedPath = Resolve-CachedArchive -Tag $tag -AssetName $asset.name -ExpectedSize $asset.size

    if ($cachedPath) {
      Write-Log "Using cached download: $cachedPath"
      $archivePath = $cachedPath
    }
    elseif ($NoCache) {
      $archivePath = Join-Path $workDir $asset.name
      Write-Log "Downloading..."
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath
    }
    else {
      $archivePath = Get-CachePath -Tag $tag -AssetName $asset.name
      New-Item -ItemType Directory -Force -Path (Split-Path $archivePath -Parent) | Out-Null

      Write-Log "Downloading..."
      try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath
      }
      catch {
        Remove-Item -Force $archivePath -ErrorAction SilentlyContinue
        throw
      }
    }

    $extractDir = Join-Path $workDir "extracted"
    Write-Log "Extracting..."
    Expand-ReleaseArchive -ArchivePath $archivePath -DestDir $extractDir

    $installSource = Resolve-NormalizedExtractDir -DestDir $extractDir

    Install-ResInsight -ExtractedDir $installSource -Tag $tag
  }
  finally {
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
  }
}

Main
