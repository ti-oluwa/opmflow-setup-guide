#!/usr/bin/env bash
set -Eeuo pipefail

# ResInsight installer - Linux and macOS.
#
# ResInsight's GitHub releases do not follow a fixed asset-naming scheme
# (the project has renamed its packages several times over the years, and
# platform coverage varies release-to-release: macOS support was only
# added in 2026.06.0, and RHEL8/Ubuntu packages are newer additions too;
# most 2025 releases only shipped a Windows asset at all). Because of
# that, this script never guesses a filename: it always asks the GitHub
# API for the real list of assets attached to the chosen release, then
# pattern-matches them against the current platform. If the release
# genuinely has nothing for this platform, it says so instead of
# downloading the wrong thing or silently failing.

readonly REPO="OPM/ResInsight"
readonly API_BASE="https://api.github.com/repos/${REPO}"

readonly DEFAULT_VERSION="latest"
readonly DEFAULT_TOOLCHAIN="gcc"
readonly DEFAULT_INSTALL_ROOT_LINUX="/opt/resinsight"
readonly DEFAULT_INSTALL_ROOT_MACOS="/Applications"
readonly DEFAULT_SYMLINK="/usr/local/bin/resinsight"
readonly DEFAULT_SEGYIMPORT_SYMLINK="/usr/local/bin/resinsight-segyimport"

RESINSIGHT_VERSION="$DEFAULT_VERSION"
TOOLCHAIN="$DEFAULT_TOOLCHAIN"
INSTALL_ROOT=""
FORCE_REINSTALL=false
USE_CACHE=true
INSTALL_DESKTOP_ENTRY=true

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
# Run a command directly if the target path is writable, otherwise via
# sudo. This mirrors what install_macos already did for /Applications -
# applied consistently here so a plain (non-root) invocation on Linux
# gets prompted for sudo exactly when it's actually needed, rather than
# failing outright (the "mkdir: Permission denied" bug) or requiring the
# whole script to be re-run under sudo from the start.
#
run_privileged() {
  local target_dir="$1"
  shift

  if [[ -w "$target_dir" ]]; then
    "$@"
    return
  fi

  if [[ $EUID -eq 0 ]]; then
    "$@"
    return
  fi

  command -v sudo >/dev/null 2>&1 ||
    die "No write access to ${target_dir} and 'sudo' is not available.

    Re-run this installer as root, or pass --install-root to install
    somewhere you own, e.g.:

        ./resinsight-setup.sh --install-root \"\$HOME/resinsight\""

  warn "No write access to ${target_dir} - using sudo for this step."
  sudo "$@"
}

#
# Detect OS + architecture, and build the set of regex patterns that a
# release asset's filename must match to be considered "for this
# platform". Kept as patterns (not a single fixed name) since the
# project's own naming has changed release to release - the current
# release alone ships RHEL8, two different Ubuntu 24.04 toolchain
# builds, and a single unsuffixed macOS build, none of which match a
# single naive pattern.
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
      CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/resinsight-setup"
      detect_linux_asset_patterns
    ;;

    Darwin)
      PLATFORM_OS="macos"
      INSTALL_ROOT="${INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT_MACOS}"
      CACHE_DIR="$HOME/Library/Caches/resinsight-setup"

      #
      # As of 2026.06.1 ResInsight ships a single unsuffixed
      # macOS build (no per-arch asset), so an arch-specific
      # pattern is tried first in case that ever changes, with
      # a bare 'mac'/'macos' fallback matching today's reality.
      #
      case "$arch" in
        arm64)
          ASSET_PATTERNS=('mac.*arm64' 'macos.*arm64' 'arm64.*mac' 'mac' 'macos')
        ;;
        x86_64)
          ASSET_PATTERNS=('mac.*(x64|x86_64|intel)' '(x64|x86_64|intel).*mac' 'mac' 'macos')
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
# Read /etc/os-release to tell RHEL-family from Debian/Ubuntu-family,
# since they get genuinely different packages (an 'el8' tarball vs.
# toolchain-specific Ubuntu zips) rather than one generic "Linux"
# asset. Falls back to trying every known pattern, in priority order,
# if the distro can't be identified.
#
detect_linux_asset_patterns() {
  local id="" id_like=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  local ubuntu_patterns
  if [[ "$TOOLCHAIN" == "clang" ]]; then
    ubuntu_patterns=('ubuntu.*clang' 'ubuntu')
  else
    ubuntu_patterns=('ubuntu.*gcc' 'ubuntu')
  fi

  case "${id} ${id_like}" in

    *rhel*|*centos*|*rocky*|*alma*|*fedora*|*ol\ *)
      ASSET_PATTERNS=('el[0-9]+' 'rhel')
    ;;

    *ubuntu*|*debian*)
      ASSET_PATTERNS=("${ubuntu_patterns[@]}")
    ;;

    *)
      warn "Could not identify the Linux distribution from /etc/os-release; trying all known Linux asset patterns."
      ASSET_PATTERNS=('el[0-9]+' 'rhel' "${ubuntu_patterns[@]}" 'linux')
    ;;
  esac
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
    # Accept the version with or without a leading 'v'. The repo's
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
# Extract "name<TAB>browser_download_url<TAB>size" for every asset, one
# per line. Deliberately avoids a JSON parser dependency (jq is not
# guaranteed to be installed). The GitHub API always emits one "name",
# one "browser_download_url", and one "size" field per asset object,
# each on its own line when the response isn't minified, which curl's
# default output is not.
#
list_assets() {
  local json="$1"

  python3 - "$json" <<'PYEOF'
import json
import sys

data = json.loads(sys.argv[1])
for asset in data.get("assets", []):
    print(f"{asset['name']}\t{asset['browser_download_url']}\t{asset['size']}")
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

  Older ResInsight releases published Windows-only assets; macOS, RHEL8,
  and Ubuntu packages were all added later and won't exist on older
  releases. Try a newer --version, or check
  https://github.com/${REPO}/releases yourself."
}

#
# Returns the cache path an asset would live at for a given release,
# namespaced by tag, not just by asset name, since at least one
# current asset (ResInsight-RHEL8.zip) has a static filename with no
# version embedded in it. Keying by name alone would risk silently
# reusing a stale archive from a previous release once that project
# ever ships a new version under the same filename.
#
cache_path_for() {
  local tag="$1"
  local asset_name="$2"

  printf '%s\n' "${CACHE_DIR}/${tag}/${asset_name}"
}

#
# Checks whether a valid cached copy of this exact asset already
# exists (present, matches the size GitHub reports for it) and prints
# its path if so. A size mismatch is treated as a corrupt/partial
# leftover from an interrupted download, not a valid cache hit.
#
resolve_cached_archive() {
  local tag="$1"
  local asset_name="$2"
  local expected_size="$3"

  [[ "$USE_CACHE" == "true" ]] || return 1

  local cached
  cached="$(cache_path_for "$tag" "$asset_name")"

  [[ -f "$cached" ]] || return 1

  local actual_size
  actual_size="$(wc -c < "$cached" 2>/dev/null | tr -d ' ')"

  if [[ "$actual_size" != "$expected_size" ]]; then
    warn "Cached archive size mismatch (expected ${expected_size} bytes, found ${actual_size}); ignoring and re-downloading."
    rm -f "$cached"
    return 1
  fi

  printf '%s\n' "$cached"
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
# directory, sometimes the files directly, and as it turns out for
# at least the RHEL8 asset, a single nested .tar.gz that itself needs
# extracting before there's anything to find). This loops flattening a
# lone wrapping directory and unwrapping a lone nested archive file,
# in whatever order/combination they show up, until neither applies.
# Capped so a pathological or unexpected archive can't loop forever.
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

normalize_extracted_dir() {
  local dest="$1"
  local max_iterations=5
  local i

  for ((i = 0; i < max_iterations; i++)); do
    flatten_single_subdir "$dest"

    local entries=("$dest"/*)
    if [[ ${#entries[@]} -eq 1 && -f "${entries[0]}" ]]; then
      case "${entries[0]}" in
        *.zip|*.tar.gz|*.tgz)
          local nested="${entries[0]}"
          log "Found a nested archive inside the download, extracting: $(basename "$nested")"

          local inner_dest
          inner_dest="$(mktemp -d)"
          extract_archive "$nested" "$inner_dest"
          rm -f "$nested"

          mv "$inner_dest"/* "$dest"/ 2>/dev/null || true
          mv "$inner_dest"/.[!.]* "$dest"/ 2>/dev/null || true
          rmdir "$inner_dest"

          continue
        ;;
      esac
    fi

    return
  done

  warn "Archive nesting went ${max_iterations} levels deep without bottoming out; proceeding with what's there."
}

#
# ResInsight's own 'resinsight' launcher script (bin/resinsight)
# determines its own directory via the shell's $_ variable and does
# 'cd "$(dirname "$_")"' before exec'ing the real binary. That only
# happens to work if you're already sitting in its own directory when
# you run it - $_ does not reliably resolve to the script's real
# location through a symlink, and on several systems it's simply empty
# by the time that line runs, silently falling back to the current
# directory instead of the install directory. A plain symlink to that
# script (or even exec'ing it via its real absolute path) does not fix
# this. The only reliable fix is to bypass their launcher entirely: cd
# into the real, known-at-install-time bin/ directory ourselves and
# exec the actual ResInsight binary directly. -name (not -iname) is
# used throughout so this can't accidentally match their launcher
# script (lowercase 'resinsight') instead of the real binary.
#
find_binary_exact() {
  local target="$1"
  local exact_name="$2"

  find "$target" -maxdepth 3 -type f -name "$exact_name" 2>/dev/null | head -n1
}

#
# Writes a small wrapper at $1 that cd's into the real bin/ directory
# ($2) and execs the actual binary ($3) from there, rather than
# symlinking to it directly - see find_binary_exact's comment above
# for why a symlink doesn't work here. Falls back to sudo for the
# write the same way run_privileged does elsewhere, since this can
# land in /usr/local/bin.
#
write_launcher_wrapper() {
  local wrapper_path="$1"
  local bin_dir="$2"
  local exe_name="$3"
  local pass_startdir="$4"

  local tmp_wrapper
  tmp_wrapper="$(mktemp)"

  if [[ "$pass_startdir" == "true" ]]; then
    # Preserve the vendor script's actual intent: the GUI's default
    # file-open location should be wherever the user ran the command
    # from, not the install directory we're about to cd into.
    cat > "$tmp_wrapper" <<EOF
#!/bin/sh
WORKING_DIR="\$(pwd)"
cd "${bin_dir}" || exit 1
exec ./${exe_name} --startdir "\$WORKING_DIR" "\$@"
EOF
  else
    # SEGYImport is a plain CLI tool with no concept of --startdir.
    cat > "$tmp_wrapper" <<EOF
#!/bin/sh
cd "${bin_dir}" || exit 1
exec ./${exe_name} "\$@"
EOF
  fi

  #
  # Explicit octal mode, not symbolic '+x': mktemp creates this file
  # at 600 (owner-only, no bits for group/other), and '+x' without an
  # explicit who= is masked by the current umask. Under a restrictive
  # umask (root/sudo sessions often use 077 rather than a regular
  # user's 022), that silently leaves the execute bit unset for
  # everyone but root (installable and even runnable via sudo), but
  # "Permission denied" for the exact command this is meant to expose
  # to a normal user.
  #
  chmod 0755 "$tmp_wrapper"

  if [[ -w "$(dirname "$wrapper_path")" ]] || [[ $EUID -eq 0 ]]; then
    mv "$tmp_wrapper" "$wrapper_path"
  elif command -v sudo >/dev/null 2>&1; then
    sudo mv "$tmp_wrapper" "$wrapper_path"
  else
    rm -f "$tmp_wrapper"
    warn "No write access to $(dirname "$wrapper_path") and no sudo available - skipped creating: ${wrapper_path}"
    return 1
  fi
}

#
# Whether the requested version is already installed at the given
# target path, so a re-run doesn't redownload/re-extract an archive
# that's already there. A version marker file is used rather than
# trusting the directory's mere existence, since on Linux the install
# directory is itself named after the tag (a reasonable signal on its
# own) but on macOS the install path is always ResInsight.app
# regardless of version. Only the marker actually distinguishes them.
#
version_marker_path() {
  local target="$1"

  printf '%s\n' "${target}.installed-version"
}

is_already_installed() {
  local target="$1"
  local tag="$2"

  [[ -d "$target" ]] || return 1

  local marker
  marker="$(version_marker_path "$target")"

  [[ -f "$marker" ]] || return 1
  [[ "$(cat "$marker" 2>/dev/null)" == "$tag" ]] || return 1

  #
  # Guard against a marker left behind by an interrupted install:
  # confirm the real binary is actually there too before trusting it.
  #
  local binary
  binary="$(find_binary_exact "$target" "ResInsight")"
  [[ -n "$binary" && -x "$binary" ]]
}

#
# Resolves the home directory a desktop entry should be installed
# into. When this script is run via sudo (the normal case for the
# default /opt/resinsight install), $HOME is root's, not the actual
# desktop user's - SUDO_USER is used to find the real one instead.
# When run without sudo (e.g. a --install-root the user already owns),
# $HOME is already correct.
#
resolve_desktop_home() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && command -v getent >/dev/null 2>&1; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    printf '%s\n' "$HOME"
  fi
}

install_desktop_entry() {
  local exe_path="$1"
  local target="$2"

  local desktop_home
  desktop_home="$(resolve_desktop_home)"

  [[ -n "$desktop_home" && -d "$desktop_home" ]] || {
    warn "Could not resolve a home directory for the desktop entry; skipping."
    return
  }

  local desktop_dir="${desktop_home}/.local/share/applications"
  local desktop_file="${desktop_dir}/resinsight.desktop"
  local desktop_user="${SUDO_USER:-}"

  #
  # Best-effort icon search - the package layout isn't guaranteed to
  # include one at a known path, so this is opportunistic. Desktop
  # environments fall back to a generic icon just fine if Icon= is
  # simply omitted, so a miss here is not an error.
  #
  local icon
  icon="$(find "$target" -maxdepth 4 -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.xpm' \) 2>/dev/null \
    | grep -i 'resinsight\|icon' | head -n1 || true)"
  if [[ -z "$icon" ]]; then
    icon="$(find "$target" -maxdepth 4 -type f \( -iname '*.png' -o -iname '*.svg' \) 2>/dev/null | head -n1 || true)"
  fi

  local tmp_desktop
  tmp_desktop="$(mktemp)"

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=ResInsight\n'
    printf 'Comment=3D visualization and post-processing of reservoir models\n'
    printf 'Exec=%s %%F\n' "$exe_path"
    [[ -n "$icon" ]] && printf 'Icon=%s\n' "$icon"
    printf 'Categories=Science;Engineering;\n'
    printf 'Terminal=false\n'
  } > "$tmp_desktop"

  #
  # Same umask trap as the launcher wrapper: mktemp starts this at
  # 600. Explicit octal mode so it's readable by everyone regardless
  # of umask - some desktop environments (GNOME/Nautilus in
  # particular) also treat the executable bit as part of trusting a
  # .desktop entry as launchable, not just parsing it, so it's set
  # here too rather than leaving it merely readable.
  #
  chmod 0755 "$tmp_desktop"

  if ! mkdir -p "$desktop_dir" 2>/dev/null; then
    warn "Could not create ${desktop_dir}; skipping desktop entry."
    rm -f "$tmp_desktop"
    return
  fi

  if [[ -n "$desktop_user" && "$desktop_user" != "root" ]]; then
    chown "$desktop_user" "$tmp_desktop" 2>/dev/null || true
  fi

  if mv "$tmp_desktop" "$desktop_file" 2>/dev/null; then
    log "Desktop entry installed: ${desktop_file}"
  else
    warn "Could not write ${desktop_file}; skipping desktop entry."
    rm -f "$tmp_desktop"
  fi
}

install_linux() {
  local extracted_dir="$1"
  local tag="$2"

  local target="${INSTALL_ROOT}/${tag}"

  if [[ -d "$target" ]]; then
    warn "Removing existing install at ${target}"
    run_privileged "$INSTALL_ROOT" rm -rf "$target"
  fi

  run_privileged "$(dirname "$INSTALL_ROOT")" mkdir -p "$INSTALL_ROOT"
  run_privileged "$INSTALL_ROOT" mv "$extracted_dir" "$target"

  local binary
  binary="$(find_binary_exact "$target" "ResInsight")"

  [[ -n "$binary" ]] ||
    die "Could not find the ResInsight executable (exact name 'ResInsight') inside:

        ${target}

    Extraction may have produced an unexpected layout - inspect it manually."

  run_privileged "$target" chmod +x "$binary"

  printf '%s\n' "$tag" > "${target}.installed-version.tmp"
  run_privileged "$INSTALL_ROOT" mv "${target}.installed-version.tmp" "$(version_marker_path "$target")"

  local bin_dir
  bin_dir="$(dirname "$binary")"

  local segyimport
  segyimport="$(find_binary_exact "$target" "SEGYImport")"

  log "Installed to ${target}"

  if write_launcher_wrapper "$DEFAULT_SYMLINK" "$bin_dir" "ResInsight" "true"; then
    log "Installed launcher: ${DEFAULT_SYMLINK} -> ${bin_dir}/ResInsight"
    log "Run it with: resinsight"
  fi

  if [[ -n "$segyimport" ]]; then
    run_privileged "$target" chmod +x "$segyimport"
    if write_launcher_wrapper "$DEFAULT_SEGYIMPORT_SYMLINK" "$(dirname "$segyimport")" "SEGYImport" "false"; then
      log "Installed launcher: ${DEFAULT_SEGYIMPORT_SYMLINK} -> $(dirname "$segyimport")/SEGYImport"
    fi
  fi

  if [[ "$INSTALL_DESKTOP_ENTRY" == "true" ]]; then
    install_desktop_entry "$DEFAULT_SYMLINK" "$target"
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
    run_privileged "$INSTALL_ROOT" rm -rf "$target"
  fi

  run_privileged "$INSTALL_ROOT" mv "$app_bundle" "$target"

  #
  # The upstream macOS build is unsigned and unnotarised (see the
  # v2026.06.0 release notes). Gatekeeper quarantines it on download
  # and refuses to launch it with "app is damaged" otherwise.
  #
  log "Removing Gatekeeper quarantine attribute (build is unsigned/unnotarised)..."
  xattr -r -d com.apple.quarantine "$target" 2>/dev/null || true

  printf '%s\n' "$tag" > "${target}.installed-version.tmp"
  run_privileged "$INSTALL_ROOT" mv "${target}.installed-version.tmp" "$(version_marker_path "$target")"

  log "Installed to ${target}"
  log "Launch it with: open '${target}'"
}

main() {
  require_tool curl
  require_tool python3
  require_tool grep

  detect_platform

  log "Resolving ResInsight release: ${RESINSIGHT_VERSION}"

  #
  # The release JSON call is a small metadata request, not a
  # download. It's always made so 'latest' resolves to a real tag,
  # even when the resolved version turns out to already be
  # installed and nothing further needs to happen.
  #
  local release_json
  release_json="$(fetch_release_json "$RESINSIGHT_VERSION")"

  local tag
  tag="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['tag_name'])" "$release_json")"

  log "Resolved to release: ${tag}"

  local target
  case "$PLATFORM_OS" in
    linux) target="${INSTALL_ROOT}/${tag}" ;;
    macos) target="${INSTALL_ROOT}/ResInsight.app" ;;
  esac

  if [[ "$FORCE_REINSTALL" != "true" ]] && is_already_installed "$target" "$tag"; then
    log "${tag} is already installed at ${target} - nothing to do."
    log "Re-run with --force to reinstall anyway."
    return
  fi

  local assets
  assets="$(list_assets "$release_json")"

  [[ -n "$assets" ]] ||
    die "Release ${tag} has no downloadable assets at all."

  local chosen
  chosen="$(select_asset "$assets" "$tag")"

  local asset_name asset_url asset_size
  asset_name="$(cut -f1 <<<"$chosen")"
  asset_url="$(cut -f2 <<<"$chosen")"
  asset_size="$(cut -f3 <<<"$chosen")"

  log "Selected asset: ${asset_name}"

  local workdir
  workdir="$(mktemp -d)"
  #
  # Double-quoted so $workdir is expanded now, embedding the literal
  # path into the trap command. The EXIT trap only fires after main()
  # has already returned, at which point this 'local' variable is out
  # of scope. A single-quoted trap would defer the lookup to that
  # point and hit "unbound variable" under set -u, even on a fully
  # successful run.
  #
  trap "rm -rf '$workdir'" EXIT

  local archive_path
  archive_path="$(resolve_cached_archive "$tag" "$asset_name" "$asset_size" || true)"

  if [[ -n "$archive_path" ]]; then
    log "Using cached download: ${archive_path}"
  else
    if [[ "$USE_CACHE" == "true" ]]; then
      archive_path="$(cache_path_for "$tag" "$asset_name")"
      mkdir -p "$(dirname "$archive_path")"
    else
      archive_path="${workdir}/${asset_name}"
    fi

    log "Downloading..."
    if ! curl -sSL -o "$archive_path" "$asset_url"; then
      rm -f "$archive_path"
      die "Failed to download:

      ${asset_url}"
    fi
  fi

  local extract_dir="${workdir}/extracted"
  log "Extracting..."
  extract_archive "$archive_path" "$extract_dir"
  normalize_extracted_dir "$extract_dir"

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
nothing for this platform, it says so rather than guessing. Once a
version is installed, re-running this script is a no-op unless the
release changes or --force is passed - it will not redownload or
reinstall the same version.

Downloaded archives are also cached on disk (by release + asset name)
under:

    ~/.cache/resinsight-setup           (Linux)
    ~/Library/Caches/resinsight-setup   (macOS)

so even --force or a different --install-root reuses the already-
downloaded file instead of fetching it from GitHub again, as long as
its size still matches what GitHub reports for that asset.

Usage:
    ./resinsight-setup.sh [options]

Options:
    --version VERSION    Release to install, e.g. '2026.06.1' or
                          'v2026.06.1' (default: latest)
    --install-root DIR   Where to install (default: ${DEFAULT_INSTALL_ROOT_LINUX}
                          on Linux, ${DEFAULT_INSTALL_ROOT_MACOS} on macOS)
    --toolchain TOOLCHAIN
                          On Ubuntu/Debian only: 'gcc' or 'clang', for
                          when a release ships both (default: gcc).
                          Ignored on other distros/platforms.
    --force               Reinstall even if this version is already
                          installed.
    --no-cache            Always download fresh; don't read from or
                          write to the download cache.
    --no-desktop-entry     On Linux, skip creating the application-menu
                          entry (~/.local/share/applications).
    -h, --help            Show this help and exit

Examples:
    ./resinsight-setup.sh
    ./resinsight-setup.sh --version 2026.06.1
    ./resinsight-setup.sh --version 2025.09.3
    ./resinsight-setup.sh --toolchain clang
    ./resinsight-setup.sh --force
    ./resinsight-setup.sh --force --no-cache

Installing to the default location and creating the 'resinsight'
command on PATH needs write access to ${DEFAULT_INSTALL_ROOT_LINUX} and
$(dirname "$DEFAULT_SYMLINK") - if you're not running as root, this
script will invoke sudo itself for just those steps (you'll get a
password prompt at that point). To avoid sudo entirely, install
somewhere you own instead:

    ./resinsight-setup.sh --install-root "\$HOME/resinsight"

On Linux, a ResInsight entry is also added to your application menu
(~/.local/share/applications) so it shows up alongside other installed
apps, not just as a terminal command. On macOS, the installed
ResInsight.app already appears in Launchpad and Spotlight on its own -
no extra step is needed there.

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

      --toolchain)
        [[ $# -ge 2 ]] ||
          die "--toolchain requires a value."

        TOOLCHAIN="$2"
        shift 2
      ;;

      --toolchain=*)
        TOOLCHAIN="${1#*=}"
        shift
      ;;

      --force)
        FORCE_REINSTALL=true
        shift
      ;;

      --no-cache)
        USE_CACHE=false
        shift
      ;;

      --no-desktop-entry)
        INSTALL_DESKTOP_ENTRY=false
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

  case "$TOOLCHAIN" in
    gcc|clang) ;;
    *)
      die "Unsupported --toolchain: ${TOOLCHAIN}

      Supported: gcc, clang"
    ;;
  esac
}

parse_arguments "$@"
main
