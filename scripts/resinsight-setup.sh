#!/usr/bin/env bash
set -Eeuo pipefail

# ResInsight installer - Linux and macOS.
#
# ResInsight's GitHub releases do not follow a fixed asset-naming scheme
# (the project has renamed its packages several times over the years, and
# platform coverage varies release-to-release. macOS support was only
# added in 2026.06.0, and RHEL8 packages are a test asset as of 2026.06.1;
# most 2025 releases only ship a Windows asset at all). Because of that,
# this script never guesses a filename: it always asks the GitHub API for
# the real list of assets attached to the chosen reease, then pattern-
# matches them against the current platform. If the release genuinely has
# nothing for this platform, it says so instead of downloading the
# wrong thing or silently failing.

readonly REPO="OPM/ResInsight"
readonly API_BASE="https://api.github.com/repos/${REPO}"

readonly DEFAULT_VERSION="latest"
readonly DEFAULT_INSTALL_ROOT_LINUX="/opt/resinsight"
readonly DEFAULT_INSTALL_ROOT_MACOS="/Applications"
readonly DEFAULT_SYMLINK="/usr/local/bin/resinsight"

RESINSIGHT_VERSION="$DEFAULT_VERSION"
INSTALL_ROOT=""

log() {
  printf '[resinsight] %s\n' "$*"
}

warn() {
  printf '[resinsight] warning: %s\n' "$*" >&2
}

die() {
  printf '[resinsight] error: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?

  printf '[resinsight] error: command failed at line %s: %s\n' \
    "$1" \
    "$2" >&2

  exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_tool() {
  local tool="$1"

  command -v "$tool" >/dev/null 2>&1 ||
    die "Required tool '${tool}' was not found on this system."
}

#
# Detect OS + architecture, and build the set of regex patterns that a
# release asset's filename must match to be considered "for this
# platform". Kept as patterns (not a single fixed name) since the
# project's own naming has changed release to release
#
detect_platform() {
  local kernel
  kernel="$(uname -s)"

  local arch
  arch="$(uname -m)"

  case "$kernel" in

    Linux)
      PLATFORM_OS="linux"
      INSTALL_ROOT="${INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT_LINUX}"
      #
      # The only Linux package currently published is the RHEL8
      # ('el8') tarball. Match a couple of reasonable synonyms too
      # in case naming shifts again (e.g. a future generic
      # 'linux64' asset).
      #
      ASSET_PATTERNS=('el[0-9]+' 'rhel' 'linux')
    ;;

    Darwin)
      PLATFORM_OS="macos"
      INSTALL_ROOT="${INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT_MACOS}"

      case "$arch" in
        arm64)
          ASSET_PATTERNS=('mac.*arm64' 'macos.*arm64' 'arm64.*mac')
        ;;
        x86_64)
          ASSET_PATTERNS=('mac.*(x64|x86_64|intel)' '(x64|x86_64|intel).*mac')
        ;;
        *)
          die "Unrecognized macOS architecture: ${arch}"
        ;;
      esac
    ;;

    *)
      die "Unsupported OS: ${kernel}.

      This script supports Linux and macOS. For Windows, use
      resinsight-setup.ps1 instead."
    ;;

  esac

  log "Detected platform: ${PLATFORM_OS} (${arch})"
}

#
# Fetch the release JSON for either the requested tag or GitHub's
# 'latest' pointer, and print it to stdout. 'latest' deliberately uses
# GitHub's own /releases/latest endpoint rather than the first entry of
# /releases, since that endpoint already excludes drafts/prereleases.
#
fetch_release_json() {
  local version="$1"

  local url
  if [[ "$version" == "latest" ]]; then
    url="${API_BASE}/releases/latest"
  else
    #
    # Accept the version with or without a leading 'v' - the repo's
    # tags are all 'vYYYY.MM.P', but people naturally type the
    # version as it's displayed on the releases page (e.g.
    # '2026.06.1'), not as the underlying git tag.
    #
    local tag="$version"
    [[ "$tag" == v* ]] || tag="v${tag}"

    url="${API_BASE}/releases/tags/${tag}"
  fi

  local http_code
  local response_file
  response_file="$(mktemp)"

  http_code="$(curl -sSL \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: resinsight-setup.sh' \
        -w '%{http_code}' \
        -o "$response_file" \
        "$url")" || die "Unable to reach the GitHub API at:

    ${url}"

  if [[ "$http_code" == "404" ]]; then
    rm -f "$response_file"
    die "No ResInsight release found for version '${version}'.

    Check https://github.com/${REPO}/releases for valid version tags."
  fi

  if [[ "$http_code" == "403" ]]; then
    rm -f "$response_file"
    die "GitHub API rate limit likely exceeded (unauthenticated
    requests are limited per IP). Wait a while and try again, or set
    GITHUB_TOKEN in the environment to use an authenticated request."
  fi

  if [[ "$http_code" != "200" ]]; then
    rm -f "$response_file"
    die "GitHub API returned HTTP ${http_code} for:

    ${url}"
  fi

  cat "$response_file"
  rm -f "$response_file"
}

#
# Extract "name<TAB>browser_download_url" for every asset, one per line.
# Deliberately avoids a JSON parser dependency (jq is not guaranteed to
# be installed) - the GitHub API always emits one "name" and one
# "browser_download_url" field per asset object, each on its own line
# when the response isn't minified, which curl's default output is not.
#
list_assets() {
  local json="$1"

  python3 - "$json" <<'PYEOF'
import json
import sys

data = json.loads(sys.argv[1])
for asset in data.get("assets", []):
    print(f"{asset['name']}\t{asset['browser_download_url']}")
PYEOF
}

#
# Pick the asset whose name matches one of the current platform's
# patterns. Prints "name<TAB>url" for the match, or nothing (with a
# clear message on stderr) if none match.
#
select_asset() {
  local assets="$1"
  local tag="$2"

  local pattern
  for pattern in "${ASSET_PATTERNS[@]}"; do
    local match
    match="$(printf '%s\n' "$assets" | grep -iE "$pattern" | head -n1 || true)"

    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  done

  local available
  available="$(printf '%s\n' "$assets" | cut -f1)"

  die "Release ${tag} has no asset for this platform (${PLATFORM_OS}).

  Assets actually published in this release:

  $(printf '%s\n' "$available" | sed 's/^/    /')

  Older ResInsight releases published Windows-only assets; macOS support
  was added in 2026.06.0 and RHEL8 packages first appeared as a test
  asset in 2026.06.1. Try a newer --version, or check
  https://github.com/${REPO}/releases yourself."
}

extract_archive() {
  local archive="$1"
  local dest="$2"

  mkdir -p "$dest"

  case "$archive" in
    *.zip)
      require_tool unzip
      unzip -q "$archive" -d "$dest"
    ;;
    *.tar.gz|*.tgz)
      require_tool tar
      tar -xzf "$archive" -C "$dest"
    ;;
    *)
      die "Don't know how to extract: ${archive}"
    ;;
  esac
}

#
# A zip/tarball's top-level layout varies (sometimes one wrapping
# directory, sometimes the files directly). If extraction produced
# exactly one directory at the top level, treat that as the real
# install root so we don't end up with a redundant extra directory
# level.
#
flatten_single_subdir() {
  local dest="$1"

  local entries=("$dest"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then
    local inner="${entries[0]}"
    local tmp
    tmp="$(mktemp -d)"

    mv "$inner"/* "$tmp"/ 2>/dev/null || true
    mv "$inner"/.[!.]* "$tmp"/ 2>/dev/null || true
    rmdir "$inner"
    mv "$tmp"/* "$dest"/ 2>/dev/null || true
    mv "$tmp"/.[!.]* "$dest"/ 2>/dev/null || true
    rmdir "$tmp"
  fi
}

install_linux() {
  local extracted_dir="$1"
  local tag="$2"

  local target="${INSTALL_ROOT}/${tag}"

  if [[ -d "$target" ]]; then
    warn "Removing existing install at ${target}"
    rm -rf "$target"
  fi

  mkdir -p "$INSTALL_ROOT"
  mv "$extracted_dir" "$target"

  local binary
  binary="$(find "$target" -maxdepth 2 -type f -iname 'ResInsight' | head -n1)"

  [[ -n "$binary" ]] ||
    die "Could not find the ResInsight executable inside:

        ${target}

    Extraction may have produced an unexpected layout - inspect it manually."

  chmod +x "$binary"

  if [[ -w "$(dirname "$DEFAULT_SYMLINK")" ]] || [[ $EUID -eq 0 ]]; then
    ln -sf "$binary" "$DEFAULT_SYMLINK"
    log "Installed to ${target}"
    log "Symlinked: ${DEFAULT_SYMLINK} -> ${binary}"
    log "Run it with: resinsight"
  else
    log "Installed to ${target}"
    warn "No write access to $(dirname "$DEFAULT_SYMLINK") - skipped
    creating a 'resinsight' symlink on PATH. Run it directly:

        ${binary}

    Or rerun this installer with sudo to get the symlink."
  fi
}

install_macos() {
  local extracted_dir="$1"
  local tag="$2"

  local app_bundle
  app_bundle="$(find "$extracted_dir" -maxdepth 2 -type d -iname '*.app' | head -n1)"

  [[ -n "$app_bundle" ]] ||
    die "Could not find a .app bundle inside the downloaded archive.

    Extraction may have produced an unexpected layout - inspect it manually
    under: ${extracted_dir}"

  local target="${INSTALL_ROOT}/ResInsight.app"

  if [[ -d "$target" ]]; then
    warn "Removing existing install at ${target}"
    rm -rf "$target"
  fi

  if [[ -w "$INSTALL_ROOT" ]]; then
    mv "$app_bundle" "$target"
  else
    warn "No write access to ${INSTALL_ROOT} - trying with sudo."
    sudo mv "$app_bundle" "$target"
  fi

  #
  # The upstream macOS build is unsigned and unnotarised (see the
  # v2026.06.0 release notes). Gatekeeper quarantines it on download
  # and refuses to launch it with "app is damaged" otherwise.
  #
  log "Removing Gatekeeper quarantine attribute (build is unsigned/unnotarised)..."
  xattr -r -d com.apple.quarantine "$target" 2>/dev/null || true

  log "Installed to ${target}"
  log "Launch it with: open '${target}'"
}

main() {
  require_tool curl
  require_tool python3
  require_tool grep

  detect_platform

  log "Resolving ResInsight release: ${RESINSIGHT_VERSION}"

  local release_json
  release_json="$(fetch_release_json "$RESINSIGHT_VERSION")"

  local tag
  tag="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['tag_name'])" "$release_json")"

  log "Resolved to release: ${tag}"

  local assets
  assets="$(list_assets "$release_json")"

  [[ -n "$assets" ]] ||
    die "Release ${tag} has no downloadable assets at all."

  local chosen
  chosen="$(select_asset "$assets" "$tag")"

  local asset_name="${chosen%%$'\t'*}"
  local asset_url="${chosen#*$'\t'}"

  log "Selected asset: ${asset_name}"

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  local archive_path="${workdir}/${asset_name}"

  log "Downloading..."
  curl -sSL -o "$archive_path" "$asset_url" ||
    die "Failed to download:

    ${asset_url}"

  local extract_dir="${workdir}/extracted"
  log "Extracting..."
  extract_archive "$archive_path" "$extract_dir"
  flatten_single_subdir "$extract_dir"

  case "$PLATFORM_OS" in
    linux)
      install_linux "$extract_dir" "$tag"
    ;;
    macos)
      install_macos "$extract_dir" "$tag"
    ;;
  esac
}

show_help() {
  cat <<EOF
ResInsight installer (Linux, macOS)

Downloads and installs a ResInsight release from:

    https://github.com/${REPO}/releases

Platform support varies by release - this script queries the GitHub API
for the actual assets published under the chosen release and picks the
one matching this machine's OS/architecture. If that release has
nothing for this platform, it says so rather than guessing.

Usage:
    ./resinsight-setup.sh [options]

Options:
    --version VERSION   Release to install, e.g. '2026.06.1' or
                         'v2026.06.1' (default: latest)
    --install-root DIR  Where to install (default: ${DEFAULT_INSTALL_ROOT_LINUX}
                         on Linux, ${DEFAULT_INSTALL_ROOT_MACOS} on macOS)
    -h, --help           Show this help and exit

Examples:
    ./resinsight-setup.sh
    ./resinsight-setup.sh --version 2026.06.1
    ./resinsight-setup.sh --version 2025.09.3

On Linux, installing to the default location and creating the
'resinsight' symlink on PATH requires sudo:

    sudo ./resinsight-setup.sh

For Windows, use resinsight-setup.ps1 instead. This script requires a
POSIX shell and does not run natively on Windows outside WSL.
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in

      --version)
        [[ $# -ge 2 ]] ||
          die "--version requires a value."

        RESINSIGHT_VERSION="$2"
        shift 2
      ;;

      --version=*)
        RESINSIGHT_VERSION="${1#*=}"
        shift
      ;;

      --install-root)
        [[ $# -ge 2 ]] ||
          die "--install-root requires a value."

        INSTALL_ROOT="$2"
        shift 2
      ;;

      --install-root=*)
        INSTALL_ROOT="${1#*=}"
        shift
      ;;

      -h|--help)
        show_help
        exit 0
      ;;

      *)
        die "Unknown argument: $1

        Run with --help for usage."
      ;;

    esac
  done
}

parse_arguments "$@"
mainl
