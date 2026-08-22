# Requires -Version 5.1
<#
.SYNOPSIS
    ResInsight installer for Windows.

.DESCRIPTION
    Downloads and installs a ResInsight release from
    https://github.com/OPM/ResInsight/releases

    ResInsight's release assets don't follow a fixed naming scheme across
    versions (the project has renamed its packages more than once, and
    platform coverage varies release to release - macOS support only
    arrived in 2026.06.0, RHEL8 packages are a test asset as of
    2026.06.1). Because of that, this script never guesses a filename:
    it always asks the GitHub API for the real list of assets attached
    to the chosen release, then picks the one that looks like a Windows
    build. If that release genuinely has nothing for Windows, it says so
    rather than downloading the wrong thing.

.PARAMETER Version
    Release to install, e.g. '2026.06.1' or 'v2026.06.1'. Defaults to
    the latest published release.

.PARAMETER InstallRoot
    Where to install. Defaults to
    "$env:LOCALAPPDATA\ResInsight".

.PARAMETER AddToPath
    If set, prepends the installed version's folder to the current
    user's PATH environment variable (persisted via setx).

.EXAMPLE
    .\resinsight-setup.ps1

.EXAMPLE
    .\resinsight-setup.ps1 -Version 2026.06.1

.EXAMPLE
    .\resinsight-setup.ps1 -Version 2025.09.3 -AddToPath
#>

[CmdletBinding()]
param(
  [string]$Version = "latest",
  [string]$InstallRoot = "$env:LOCALAPPDATA\ResInsight",
  [switch]$AddToPath
)

$ErrorActionPreference = "Stop"

$Repo = "OPM/ResInsight"
$ApiBase = "https://api.github.com/repos/$Repo"

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
    # Accept the version with or without a leading 'v' - the repo's
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

Try a different --Version, or check https://github.com/$Repo/releases yourself.
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
  else {
    Die "Don't know how to extract: $ArchivePath (expected a .zip for Windows)"
  }
}

# If extraction produced exactly one directory at the top level, treat
# that as the real install root so we don't end up with a redundant
# extra directory level (mirrors resinsight-setup.sh's behavior).
function Resolve-SingleSubdir {
  param([string]$DestDir)

  $entries = Get-ChildItem -Path $DestDir
  if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
    return $entries[0].FullName
  }
  return $DestDir
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

  Write-Log "Installed to $target"
  Write-Log "Executable: $($exe.FullName)"

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

  $release = Get-ReleaseJson -RequestedVersion $Version
  $tag = $release.tag_name

  Write-Log "Resolved to release: $tag"

  if (-not $release.assets -or $release.assets.Count -eq 0) {
    Die "Release $tag has no downloadable assets at all."
  }

  $asset = Select-WindowsAsset -Release $release
  Write-Log "Selected asset: $($asset.name)"

  $workDir = Join-Path $env:TEMP ("resinsight-setup-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $workDir | Out-Null

  try {
    $archivePath = Join-Path $workDir $asset.name

    Write-Log "Downloading..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archivePath

    $extractDir = Join-Path $workDir "extracted"
    Write-Log "Extracting..."
    Expand-ReleaseArchive -ArchivePath $archivePath -DestDir $extractDir

    $installSource = Resolve-SingleSubdir -DestDir $extractDir

    Install-ResInsight -ExtractedDir $installSource -Tag $tag
  }
  finally {
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
  }
}

Main
