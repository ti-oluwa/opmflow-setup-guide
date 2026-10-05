#!/usr/bin/env bash
set -Eeuo pipefail

#
# ResInsight uninstaller for Linux and macOS.
#
# This is the counterpart to resinsight-setup.sh. It removes only what
# that installer put on this computer:
#
#     Linux
#         /opt/resinsight/<version>/         the program (one folder per version)
#         /opt/resinsight/<version>.installed-version   its version marker
#         /usr/local/bin/resinsight          the 'resinsight' command
#         /usr/local/bin/resinsight-segyimport          the SEGYImport command
#         ~/.local/share/applications/resinsight.desktop  the menu entry
#         ~/.cache/resinsight-setup/         the download cache and menu icon
#
#     macOS
#         /Applications/ResInsight.app       the program
#         /Applications/ResInsight.app.installed-version  its version marker
#         ~/Library/Caches/resinsight-setup  the download cache
#
# How it decides what is "ours":
#
#   - A program folder is only removed if the installer's own version
#     marker sits next to it and names that same version. A folder that
#     merely looks similar, or an unrelated ResInsight.app you installed
#     some other way, is never touched.
#   - The commands in /usr/local/bin are only removed if they are the
#     small launcher scripts this installer writes AND they point at a
#     version being removed. If you have two versions installed and
#     remove just one, a launcher that still points at the other one is
#     left working.
#   - The menu entry is only removed if it is the one this installer
#     wrote, and only once no 'resinsight' command remains for it to
#     start.
#
# Nothing is removed with a broad pattern. Every deletion is of a
# specific path that was identified first and shown to you beforehand.
#
# Your ResInsight project files, and ResInsight's own saved preferences
# (for example its list of recent files), were never created by the
# installer and are not touched.
#

readonly DEFAULT_INSTALL_ROOT_LINUX="/opt/resinsight"
readonly DEFAULT_INSTALL_ROOT_MACOS="/Applications"
readonly LAUNCHER_PATH="/usr/local/bin/resinsight"
readonly SEGYIMPORT_LAUNCHER_PATH="/usr/local/bin/resinsight-segyimport"

ONLY_VERSION=""
INSTALL_ROOT=""
KEEP_CACHE=false
ASSUME_YES=false
DRY_RUN=false

PLATFORM_OS=""
ONLY_TAG=""

#
# What inspect_system() finds. Newline separated strings instead of
# arrays so this also runs on the old bash 3.2 that ships with macOS,
# where expanding an empty array is an error under 'set -u'.
#
INSTALLS=""          # lines of: tag|program folder|marker file
STRAY_MARKERS=""     # version markers whose program folder is already gone
FOREIGN_NOTES=""     # things that look related but are not ours (kept)
LAUNCHER_DECISION="absent"    # absent | remove | keep | foreign
SEGYIMPORT_DECISION="absent"  # absent | remove | keep | foreign
DESKTOP_FILE=""
DESKTOP_DECISION="absent"     # absent | remove | keep | foreign
CACHE_DIRS=""        # cache folders to remove, one per line
ICON_FILES=""        # menu icon files to remove, one per line
CACHE_ROOTS=""       # resinsight-setup folders to tidy up if left empty

DONE=""
LEFT=""
FAILURES=0

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

note_done() {
  DONE+="$1"$'\n'
}

note_left() {
  LEFT+="$1"$'\n'
}

#
# Counting with $(( )) rather than '(( FAILURES++ ))' on purpose: the
# latter evaluates to 0 the first time and 'set -e' treats that as a
# failure, which would abort the script on the very first problem.
#
note_failure() {
  FAILURES=$(( FAILURES + 1 ))
}

#
# Same idea as in resinsight-setup.sh: run a command directly if the
# target folder is writable, otherwise via sudo, so a plain invocation
# is only asked for a password at the moment one is actually needed.
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

    Re-run this uninstaller as root."

  warn "No write access to ${target_dir} - using sudo for this step."
  sudo "$@"
}

show_help() {
  cat <<EOF
ResInsight uninstaller (Linux, macOS)

Removes what resinsight-setup.sh installed: the program, the
'resinsight' command, the application-menu entry (Linux), and the
download cache. It does not touch your ResInsight project files or
ResInsight's own saved preferences.

Usage:
    ./resinsight-uninstall.sh [options]
    sudo ./resinsight-uninstall.sh [options]

Use sudo if you installed with sudo (the default). If you installed into
a folder you own with --install-root, no sudo is needed. The script asks
for your password itself, only for the steps that need it.

Options:
    --dry-run             Show what would be removed, and change nothing.
    --version VERSION     Remove only this version, e.g. '2026.06.1' or
                          'v2026.06.1'. By default every version found
                          is removed.
    --install-root DIR    Where ResInsight was installed (default:
                          ${DEFAULT_INSTALL_ROOT_LINUX} on Linux,
                          ${DEFAULT_INSTALL_ROOT_MACOS} on macOS). Use the same
                          value you gave the installer, if you gave one.
    --keep-cache          Keep the downloaded installer files, so that a
                          later reinstall does not need to download them
                          again.
    -y, --yes             Do not ask for confirmation. Useful in scripts.
    -h, --help            Show this help and exit

Examples:
    ./resinsight-uninstall.sh --dry-run
    sudo ./resinsight-uninstall.sh
    sudo ./resinsight-uninstall.sh --version 2026.06.0
    ./resinsight-uninstall.sh --install-root "\$HOME/resinsight"
    sudo ./resinsight-uninstall.sh --keep-cache --yes
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in

      --dry-run)
        DRY_RUN=true
        shift
      ;;

      --version)
        [[ $# -ge 2 ]] ||
          die "--version requires a value."

        ONLY_VERSION="$2"
        shift 2
      ;;

      --version=*)
        ONLY_VERSION="${1#*=}"
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

      --keep-cache)
        KEEP_CACHE=true
        shift
      ;;

      -y|--yes)
        ASSUME_YES=true
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

detect_platform() {
  local kernel
  kernel="$(uname -s)"

  case "$kernel" in

    Linux)
      PLATFORM_OS="linux"
      INSTALL_ROOT="${INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT_LINUX}"
    ;;

    Darwin)
      PLATFORM_OS="macos"
      INSTALL_ROOT="${INSTALL_ROOT:-$DEFAULT_INSTALL_ROOT_MACOS}"
    ;;

    *)
      die "Unsupported OS: ${kernel}.

      This script supports Linux and macOS. For Windows, use
      resinsight-uninstall.ps1 instead."
    ;;

  esac

  if [[ -n "$ONLY_VERSION" ]]; then
    #
    # People type the version as it appears on the releases page
    # ('2026.06.1'); the installer's folders and markers use the git
    # tag ('v2026.06.1'). Accept either.
    #
    ONLY_TAG="$ONLY_VERSION"
    [[ "$ONLY_TAG" == v* ]] || ONLY_TAG="v${ONLY_TAG}"

    valid_tag "$ONLY_TAG" ||
      die "Invalid version: ${ONLY_VERSION}

      Expected something like: 2026.06.1"
  fi
}

#
# A version tag becomes part of a folder path that gets deleted, so it
# is validated strictly: only letters, digits, dots, dashes and
# underscores, must start with a letter or digit, and no '..'. That
# rules out anything containing a slash or that could climb out of the
# install folder.
#
valid_tag() {
  local tag="$1"

  [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ "$tag" != *..* ]]
}

#
# Same logic as resinsight-setup.sh. When this runs under sudo, $HOME
# may be root's rather than the real desktop user's, and the installer
# put the menu entry and icon in the real user's home, so the same
# lookup is needed here to find them again.
#
resolve_desktop_home() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && command -v getent >/dev/null 2>&1; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    printf '%s\n' "${HOME:-}"
  fi
}

#
# True if path $1 is the same as, or inside, folder $2.
#
path_within() {
  local path="${1%/}"
  local dir="${2%/}"

  [[ -n "$dir" ]] || return 1

  [[ "$path" == "$dir" || "$path" == "$dir"/* ]]
}

canonical_dir() {
  ( cd "$1" 2>/dev/null && pwd -P ) || true
}

size_of() {
  du -sh "$1" 2>/dev/null | cut -f1 || true
}

#
# Looks for every version this installer put under INSTALL_ROOT. A
# version counts only if its marker file exists, is a plain file, and
# names the same version as the folder it sits next to.
#
add_install() {
  local tag="$1"
  local target="$2"
  local marker="$3"

  if [[ -n "$ONLY_TAG" && "$tag" != "$ONLY_TAG" ]]; then
    return
  fi

  if [[ -L "$target" ]]; then
    FOREIGN_NOTES+="${target}  (a link, not a folder the installer made, left alone)"$'\n'
  elif [[ -d "$target" ]]; then
    INSTALLS+="${tag}|${target}|${marker}"$'\n'
  elif [[ ! -e "$target" ]]; then
    STRAY_MARKERS+="${marker}"$'\n'
  fi
}

find_installs() {
  [[ -d "$INSTALL_ROOT" ]] || return 0

  local marker name tag

  if [[ "$PLATFORM_OS" == "linux" ]]; then
    for marker in "$INSTALL_ROOT"/*.installed-version; do
      [[ -f "$marker" && ! -L "$marker" ]] || continue

      name="$(basename "$marker")"
      name="${name%.installed-version}"
      tag="$(tr -d '[:space:]' < "$marker")"

      [[ "$tag" == "$name" ]] || continue
      valid_tag "$tag" || continue

      add_install "$tag" "${INSTALL_ROOT}/${name}" "$marker"
    done
    return
  fi

  #
  # macOS: the app is always called ResInsight.app regardless of
  # version, so only the marker's content says which version it is.
  #
  marker="${INSTALL_ROOT}/ResInsight.app.installed-version"
  local app="${INSTALL_ROOT}/ResInsight.app"

  if [[ -f "$marker" && ! -L "$marker" ]]; then
    tag="$(tr -d '[:space:]' < "$marker")"

    if valid_tag "$tag"; then
      add_install "$tag" "$app" "$marker"
    fi
  elif [[ -e "$app" ]]; then
    FOREIGN_NOTES+="${app}  (no installer version marker next to it, so it was not installed by this installer, left alone)"$'\n'
  fi
}

#
# The launcher scripts resinsight-setup.sh writes are tiny and
# recognisable: they start with '#!/bin/sh', cd into the program's bin
# folder, and exec the real binary from there.
#
is_our_launcher() {
  local path="$1"
  local exe="$2"

  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(head -n1 "$path")" == "#!/bin/sh" ]] || return 1
  grep -q "^exec \./${exe} " "$path" 2>/dev/null
}

launcher_target_dir() {
  sed -n 's/^cd "\(.*\)" || exit 1$/\1/p' "$1" | head -n1
}

#
# Decides what to do with one launcher: remove it, keep it, or leave
# it alone because it isn't ours. It is removed when it points into a
# program folder that is being removed, or when it points at a folder
# under our install root that no longer exists (a dead launcher). If
# it points anywhere else (another version we are keeping, or a
# different install location altogether) it is kept, so removing one
# version never breaks another.
#
decide_launcher() {
  local path="$1"
  local exe="$2"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    printf 'absent\n'
    return
  fi

  if ! is_our_launcher "$path" "$exe"; then
    printf 'foreign\n'
    return
  fi

  local dir
  dir="$(launcher_target_dir "$path" || true)"

  if [[ -z "$dir" ]]; then
    printf 'foreign\n'
    return
  fi

  if [[ ! -d "$dir" ]]; then
    #
    # Dead-launcher cleanup only happens when removing everything. If
    # one specific --version was asked for, nothing else is touched.
    #
    if [[ -z "$ONLY_TAG" ]] && path_within "$dir" "$INSTALL_ROOT"; then
      printf 'remove\n'
    else
      printf 'keep\n'
    fi
    return
  fi

  local canon
  canon="$(canonical_dir "$dir")"

  local tag target marker target_canon
  while IFS='|' read -r tag target marker; do
    [[ -n "$target" ]] || continue

    target_canon="$(canonical_dir "$target")"

    if path_within "$dir" "$target" || path_within "$canon" "$target_canon"; then
      printf 'remove\n'
      return
    fi
  done <<< "$INSTALLS"

  printf 'keep\n'
}

launcher_remains() {
  [[ "$LAUNCHER_DECISION" == "keep" || "$LAUNCHER_DECISION" == "foreign" ]]
}

is_our_desktop_entry() {
  local file="$1"

  [[ -f "$file" && ! -L "$file" ]] || return 1
  grep -qxF 'Name=ResInsight' "$file" 2>/dev/null &&
    grep -qxF "Exec=${LAUNCHER_PATH} %F" "$file" 2>/dev/null
}

#
# Where the installer could have left caches. Under sudo the download
# cache usually lands in root's home while the menu icon lands in the
# real user's home, so both are checked. Only folders that actually
# exist are listed.
#
candidate_cache_roots() {
  local desktop_home
  desktop_home="$(resolve_desktop_home)"

  if [[ "$PLATFORM_OS" == "linux" ]]; then
    printf '%s\n' "${XDG_CACHE_HOME:-${HOME:-}/.cache}/resinsight-setup"
    printf '%s\n' "${desktop_home}/.cache/resinsight-setup"
    [[ $EUID -ne 0 ]] || printf '%s\n' "/root/.cache/resinsight-setup"
  else
    printf '%s\n' "${HOME:-}/Library/Caches/resinsight-setup"
    printf '%s\n' "${desktop_home}/Library/Caches/resinsight-setup"
    [[ $EUID -ne 0 ]] || printf '%s\n' "/var/root/Library/Caches/resinsight-setup"
  fi
}

inspect_cache() {
  local root seen="" entry name

  while IFS= read -r root; do
    [[ -n "$root" && "$root" != "/resinsight-setup" ]] || continue
    [[ -d "$root" && ! -L "$root" ]] || continue

    case "$seen" in
      *"|${root}|"*) continue ;;
    esac
    seen+="|${root}|"

    CACHE_ROOTS+="${root}"$'\n'

    if [[ "$KEEP_CACHE" != "true" ]]; then
      if [[ -n "$ONLY_TAG" ]]; then
        [[ -d "${root}/${ONLY_TAG}" && ! -L "${root}/${ONLY_TAG}" ]] &&
          CACHE_DIRS+="${root}/${ONLY_TAG}"$'\n'
      else
        for entry in "$root"/*; do
          [[ -d "$entry" && ! -L "$entry" ]] || continue

          name="$(basename "$entry")"
          valid_tag "$name" || continue

          CACHE_DIRS+="${entry}"$'\n'
        done
      fi
    fi

    if [[ -f "${root}/resinsight-icon.png" && ! -L "${root}/resinsight-icon.png" ]]; then
      ICON_FILES+="${root}/resinsight-icon.png"$'\n'
    fi
  done <<< "$(candidate_cache_roots)"
}

inspect_system() {
  find_installs

  LAUNCHER_DECISION="$(decide_launcher "$LAUNCHER_PATH" "ResInsight")"
  SEGYIMPORT_DECISION="$(decide_launcher "$SEGYIMPORT_LAUNCHER_PATH" "SEGYImport")"

  if [[ "$PLATFORM_OS" == "linux" ]]; then
    local desktop_home
    desktop_home="$(resolve_desktop_home)"

    if [[ -n "$desktop_home" ]]; then
      DESKTOP_FILE="${desktop_home}/.local/share/applications/resinsight.desktop"

      if [[ -e "$DESKTOP_FILE" || -L "$DESKTOP_FILE" ]]; then
        if ! is_our_desktop_entry "$DESKTOP_FILE"; then
          DESKTOP_DECISION="foreign"
        elif launcher_remains; then
          DESKTOP_DECISION="keep"
        else
          DESKTOP_DECISION="remove"
        fi
      fi
    fi
  fi

  inspect_cache

  #
  # The menu icon belongs to the menu entry: it is only removed along
  # with it, otherwise a menu entry we are keeping would lose its icon.
  #
  if launcher_remains && [[ -n "$ICON_FILES" ]]; then
    ICON_FILES=""
  fi
}

nothing_to_remove() {
  [[ -z "$INSTALLS" ]] || return 1
  [[ -z "$STRAY_MARKERS" ]] || return 1
  [[ "$LAUNCHER_DECISION" != "remove" ]] || return 1
  [[ "$SEGYIMPORT_DECISION" != "remove" ]] || return 1
  [[ "$DESKTOP_DECISION" != "remove" ]] || return 1
  [[ -z "$CACHE_DIRS" ]] || return 1
  [[ -z "$ICON_FILES" ]]
}

plan() {
  printf '[resinsight]     %-9s %s\n' "$1" "$2"
}

print_plan() {
  log "ResInsight uninstaller"
  log ""
  log "Looking in: ${INSTALL_ROOT}"
  log ""
  log "Found on this computer:"
  log ""

  local tag target marker line

  while IFS='|' read -r tag target marker; do
    [[ -n "$target" ]] || continue
    plan "remove" "${target}   (ResInsight ${tag}, $(size_of "$target"))"
  done <<< "$INSTALLS"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    plan "remove" "${line}   (leftover version marker)"
  done <<< "$STRAY_MARKERS"

  case "$LAUNCHER_DECISION" in
    remove)  plan "remove" "${LAUNCHER_PATH}   (the 'resinsight' command)" ;;
    keep)    plan "keep" "${LAUNCHER_PATH}   (still points at a version that is not being removed)" ;;
    foreign) plan "keep" "${LAUNCHER_PATH}   (not created by the ResInsight installer)" ;;
  esac

  case "$SEGYIMPORT_DECISION" in
    remove)  plan "remove" "${SEGYIMPORT_LAUNCHER_PATH}   (the SEGYImport command)" ;;
    keep)    plan "keep" "${SEGYIMPORT_LAUNCHER_PATH}   (still points at a version that is not being removed)" ;;
    foreign) plan "keep" "${SEGYIMPORT_LAUNCHER_PATH}   (not created by the ResInsight installer)" ;;
  esac

  case "$DESKTOP_DECISION" in
    remove)  plan "remove" "${DESKTOP_FILE}   (application menu entry)" ;;
    keep)    plan "keep" "${DESKTOP_FILE}   (the 'resinsight' command it starts is staying)" ;;
    foreign) plan "keep" "${DESKTOP_FILE}   (not created by the ResInsight installer)" ;;
  esac

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    plan "remove" "${line}   (menu icon)"
  done <<< "$ICON_FILES"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    plan "remove" "${line}   (downloaded installer files, $(size_of "$line"))"
  done <<< "$CACHE_DIRS"

  if [[ "$KEEP_CACHE" == "true" ]]; then
    plan "keep" "downloaded installer files   (because --keep-cache was given)"
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    plan "keep" "${line}"
  done <<< "$FOREIGN_NOTES"

  log ""
  log "Not touched, on purpose:"
  log "    - your ResInsight project files"
  log "    - ResInsight's own saved preferences"
  log ""
}

confirm() {
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi

  #
  # Asks on the real terminal (/dev/tty) so the question still works if
  # this script was started through a pipe. With no terminal at all
  # (cron, CI) it refuses to guess and asks for --yes instead.
  #
  if ! : </dev/tty 2>/dev/null; then
    die "Cannot ask for confirmation because there is no terminal.

    Re-run with --yes to proceed without being asked, or use --dry-run
    to just preview."
  fi

  local answer
  read -r -p "[resinsight] Remove the items marked 'remove' above? [y/N] " answer </dev/tty

  case "$answer" in
    y|Y|yes|YES|Yes)
      return 0
    ;;
    *)
      log "Cancelled. Nothing was changed."
      exit 1
    ;;
  esac
}

#
# Removing a program folder that is currently running is not harmful
# on Linux/macOS, but the running copy would keep going from deleted
# files and the person would be confused about whether anything
# happened. Better to ask for it to be closed first.
#
check_not_running() {
  command -v pgrep >/dev/null 2>&1 || return 0

  [[ -n "$INSTALLS" ]] || return 0

  if pgrep -x ResInsight >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "true" ]]; then
      warn "ResInsight is running right now. Close it before the real uninstall."
      return 0
    fi

    die "ResInsight is running right now.

    Close it completely (File > Exit, or quit it from the menu bar on
    macOS), then run this uninstaller again."
  fi
}

remove_installs() {
  local tag target marker

  while IFS='|' read -r tag target marker; do
    [[ -n "$target" ]] || continue

    #
    # The marker is removed only after the folder is gone. If the
    # folder cannot be fully removed (for example a permission
    # problem), the marker stays, so running the uninstaller again
    # still recognises this as ours and retries.
    #
    if run_privileged "$INSTALL_ROOT" rm -rf "$target"; then
      run_privileged "$INSTALL_ROOT" rm -f "$marker"
      note_done "ResInsight ${tag}  (${target})"
    else
      warn "Could not fully remove ${target}"
      note_left "ResInsight ${tag}  (${target}), could not be removed"
      note_failure
    fi
  done <<< "$INSTALLS"

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    if run_privileged "$INSTALL_ROOT" rm -f "$line"; then
      note_done "Leftover version marker  (${line})"
    else
      note_left "${line}, could not be removed"
      note_failure
    fi
  done <<< "$STRAY_MARKERS"

  #
  # Tidy up the install folder itself only when it is the default one
  # this installer creates (/opt/resinsight) and it is now empty.
  # A folder you chose yourself with --install-root is yours, so it is
  # left in place even when empty. rmdir only ever removes an empty
  # folder.
  #
  if [[ "$PLATFORM_OS" == "linux" && "$INSTALL_ROOT" == "$DEFAULT_INSTALL_ROOT_LINUX" && -d "$INSTALL_ROOT" ]]; then
    run_privileged "$(dirname "$INSTALL_ROOT")" rmdir "$INSTALL_ROOT" 2>/dev/null || true
  fi
}

remove_launcher() {
  local path="$1"
  local decision="$2"
  local description="$3"

  case "$decision" in
    remove)
      if run_privileged "$(dirname "$path")" rm -f "$path"; then
        note_done "${description}  (${path})"
      else
        warn "Could not remove ${path}"
        note_left "${description}  (${path}), could not be removed"
        note_failure
      fi
    ;;
    keep)
      note_left "${description}  (${path}), still points at a version that is not being removed"
    ;;
    foreign)
      note_left "${path}  (not created by the ResInsight installer, left alone)"
    ;;
  esac
}

remove_desktop_entry() {
  case "$DESKTOP_DECISION" in
    remove)
      if rm -f "$DESKTOP_FILE"; then
        note_done "Application menu entry  (${DESKTOP_FILE})"
      else
        warn "Could not remove ${DESKTOP_FILE}"
        note_left "Application menu entry  (${DESKTOP_FILE}), could not be removed"
        note_failure
      fi
    ;;
    keep)
      note_left "Application menu entry  (${DESKTOP_FILE}), the 'resinsight' command it starts is staying"
    ;;
    foreign)
      note_left "${DESKTOP_FILE}  (not created by the ResInsight installer, left alone)"
    ;;
  esac
}

remove_cache() {
  local line

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    if rm -rf "$line"; then
      note_done "Downloaded installer files  (${line})"
    else
      warn "Could not remove ${line}"
      note_left "${line}, could not be removed"
      note_failure
    fi
  done <<< "$CACHE_DIRS"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    if rm -f "$line"; then
      note_done "Menu icon  (${line})"
    else
      note_left "${line}, could not be removed"
      note_failure
    fi
  done <<< "$ICON_FILES"

  #
  # Remove the cache folder itself only if it is now empty, so that
  # anything unexpected someone left in it is never destroyed.
  #
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    rmdir "$line" 2>/dev/null || true
  done <<< "$CACHE_ROOTS"
}

execute() {
  remove_installs

  remove_launcher "$LAUNCHER_PATH" "$LAUNCHER_DECISION" "The 'resinsight' command"
  remove_launcher "$SEGYIMPORT_LAUNCHER_PATH" "$SEGYIMPORT_DECISION" "The SEGYImport command"

  remove_desktop_entry
  remove_cache

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    note_left "$line"
  done <<< "$FOREIGN_NOTES"

  if [[ "$KEEP_CACHE" == "true" ]]; then
    note_left "Downloaded installer files  (kept because --keep-cache was given)"
  fi
}

print_summary() {
  local line

  log ""

  if [[ -n "$DONE" ]]; then
    log "Removed:"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      log "    - ${line}"
    done <<< "$DONE"
    log ""
  fi

  if [[ -n "$LEFT" ]]; then
    log "Left in place:"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      log "    - ${line}"
    done <<< "$LEFT"
    log ""
  fi

  #
  # If the 'resinsight' command was removed but another version is
  # still installed, that version has no command any more. Say so
  # plainly, with the exact fix, rather than leaving a quiet gap.
  #
  if [[ "$LAUNCHER_DECISION" == "remove" && -n "$ONLY_TAG" ]]; then
    log "Note: the 'resinsight' command pointed at the version you removed."
    log "If you have another version installed and want the command back for"
    log "it, run the installer again for that version, for example:"
    log ""
    log "    ./resinsight-setup.sh --version <that version>"
    log ""
  fi

  log "Your project files and ResInsight's own preferences were not touched."
  log ""
  log "If this terminal still finds 'resinsight' after this, that is only the"
  log "shell remembering the old location. Run 'hash -r' or open a new"
  log "terminal window."

  if [[ $FAILURES -gt 0 ]]; then
    log ""
    warn "Finished, but ${FAILURES} item(s) could not be removed. See the messages above."
    exit 1
  fi

  log ""
  log "ResInsight uninstall completed."
}

#
# The installer does not record where it installed to. If the
# 'resinsight' command exists and points somewhere other than the
# folder we searched, that is the most likely reason no program was
# found, so say where to look instead of just giving up.
#
hint_other_location() {
  [[ "$LAUNCHER_DECISION" == "keep" ]] || return 0
  is_our_launcher "$LAUNCHER_PATH" "ResInsight" || return 0

  log ""
  log "However, the 'resinsight' command (${LAUNCHER_PATH}) points at:"
  log ""
  log "    $(launcher_target_dir "$LAUNCHER_PATH" || true)"
  log ""
  log "so ResInsight may be installed somewhere other than ${INSTALL_ROOT}."
  log "If you gave the installer a custom --install-root, give the same one"
  log "here, for example:"
  log ""
  log "    ./resinsight-uninstall.sh --install-root /that/folder"
  log ""
}

explain_nothing_found() {
  if [[ -n "$ONLY_TAG" ]]; then
    log "Version ${ONLY_VERSION} was not found under ${INSTALL_ROOT}."
    log "Run without --version to see everything that is installed there."
    return
  fi

  log "Nothing to remove under ${INSTALL_ROOT}."
  hint_other_location
}

main() {
  parse_arguments "$@"
  detect_platform

  #
  # Use the folder as it was typed (so it still matches the paths the
  # installer wrote into its launcher), just made absolute.
  #
  if [[ -d "$INSTALL_ROOT" ]]; then
    INSTALL_ROOT="$(cd "$INSTALL_ROOT" && pwd)"
  fi

  if [[ "$INSTALL_ROOT" == "/" || -z "$INSTALL_ROOT" ]]; then
    die "Refusing to use '/' as the install folder."
  fi

  inspect_system

  if nothing_to_remove; then
    print_plan
    explain_nothing_found
    exit 0
  fi

  print_plan

  if [[ -z "$INSTALLS" && -z "$ONLY_TAG" ]]; then
    log "No ResInsight program folder was found under ${INSTALL_ROOT}."
    hint_other_location
  fi

  check_not_running

  if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run: nothing was changed."
    log "To really uninstall, run the same command without --dry-run."
    exit 0
  fi

  confirm
  execute
  print_summary
}

main "$@"
