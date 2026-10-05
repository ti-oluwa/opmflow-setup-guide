#!/usr/bin/env bash
set -Eeuo pipefail

#
# OPM Flow uninstaller for Linux and macOS.
#
# This is the counterpart to opmflow-setup.sh. It removes only what that
# installer put on this computer:
#
#     /usr/local/bin/opmflow     the command (a small wrapper script)
#     /usr/local/bin/flow        a link to the command above
#     /etc/opm-flow/             the saved version/variant settings
#     the OPM Flow Docker images that were downloaded
#
# What it deliberately does NOT touch:
#
#   - Docker itself. The installer does not record whether it was the
#     one that installed Docker, and Docker is very commonly used for
#     other things too, so removing it automatically could break
#     unrelated work. The README explains how to remove it yourself.
#   - Your simulation files (.DATA files, results). Those live in your
#     own folders and were never part of the install.
#
# Everything it removes is identified first. 'flow' in particular is a
# very common command name (the JavaScript type checker is also called
# flow), so a file is only deleted if it is positively recognised as
# something opmflow-setup.sh created. Anything else is left alone and
# reported.
#

readonly INSTALL_DIR="/usr/local/bin"
readonly WRAPPER_PATH="${INSTALL_DIR}/opmflow"
readonly LINK_PATH="${INSTALL_DIR}/flow"
readonly CONFIG_DIR="/etc/opm-flow"
readonly CONFIG_FILE="${CONFIG_DIR}/config"

readonly IMAGE_REPOSITORY="openporousmedia/opmreleases"

ASSUME_YES=false
DRY_RUN=false
KEEP_IMAGES=false

#
# What inspect_system() finds. Kept in plain variables (and newline
# separated strings rather than arrays) so this also runs on the old
# bash 3.2 that ships with macOS, where an empty array is an error
# under 'set -u'.
#
WRAPPER_STATE="absent"   # absent | ours | foreign
LINK_STATE="absent"      # absent | ours | foreign
CONFIG_STATE="absent"    # absent | present | unexpected
DOCKER_STATE="unknown"   # ready | missing | not_running
DOCKER_RUN_AS=""         # empty = run docker as the current user
IMAGES=""                # one image per line

DONE=""
LEFT=""
FAILURES=0

log() {
  printf '[opm-flow] %s\n' "$*"
}

warn() {
  printf '[opm-flow] warning: %s\n' "$*" >&2
}

die() {
  printf '[opm-flow] error: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?

  printf '[opm-flow] error: command failed at line %s: %s\n' \
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

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This uninstaller must be run with sudo:

    sudo ./opmflow-uninstall.sh

    To only preview what it would remove (no sudo needed, nothing is
    changed):

    ./opmflow-uninstall.sh --dry-run"
  fi
}

show_help() {
  cat <<EOF
OPM Flow uninstaller (Linux, macOS)

Removes what opmflow-setup.sh installed:

    ${WRAPPER_PATH}
    ${LINK_PATH}
    ${CONFIG_DIR}
    the downloaded OPM Flow Docker images (${IMAGE_REPOSITORY})

It does NOT remove Docker itself, and it does not touch your simulation
files. See the README for how to remove Docker separately if you want to.

Usage:

    sudo ./opmflow-uninstall.sh [options]

Options:

    --dry-run        Show what would be removed, and change nothing.
                     Needs no sudo.
    --keep-images    Remove the commands and settings, but keep the
                     downloaded Docker images (they can be large, but
                     keeping them makes a later reinstall much faster).
    -y, --yes        Do not ask for confirmation. Useful in scripts.
    -h, --help       Show this help and exit

Examples:

    ./opmflow-uninstall.sh --dry-run
    sudo ./opmflow-uninstall.sh
    sudo ./opmflow-uninstall.sh --keep-images
    sudo ./opmflow-uninstall.sh --yes
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in

      --dry-run)
        DRY_RUN=true
        shift
      ;;

      --keep-images)
        KEEP_IMAGES=true
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
        die "Unknown option: $1

        Run:

            ./opmflow-uninstall.sh --help"
      ;;

    esac
  done
}

#
# opmflow-setup.sh writes the wrapper with a known help text and a
# fixed config path. Requiring both strings means a different program
# that merely happens to be called 'opmflow' is never mistaken for ours.
#
is_our_wrapper() {
  local path="$1"

  [[ -f "$path" && ! -L "$path" ]] || return 1

  grep -q 'OPM Flow Docker wrapper' "$path" 2>/dev/null &&
    grep -q '/etc/opm-flow/config' "$path" 2>/dev/null
}

#
# The installer creates 'flow' with 'ln -sf /usr/local/bin/opmflow
# /usr/local/bin/flow', so ours is a symlink pointing at exactly that.
# A plain copy of our wrapper under the name 'flow' is accepted too.
#
is_our_link() {
  local path="$1"

  if [[ -L "$path" ]]; then
    [[ "$(readlink "$path")" == "$WRAPPER_PATH" ]]
    return
  fi

  is_our_wrapper "$path"
}

inspect_files() {
  if [[ -e "$WRAPPER_PATH" || -L "$WRAPPER_PATH" ]]; then
    if is_our_wrapper "$WRAPPER_PATH"; then
      WRAPPER_STATE="ours"
    else
      WRAPPER_STATE="foreign"
    fi
  fi

  if [[ -e "$LINK_PATH" || -L "$LINK_PATH" ]]; then
    if is_our_link "$LINK_PATH"; then
      LINK_STATE="ours"
    else
      LINK_STATE="foreign"
    fi
  fi

  if [[ -L "$CONFIG_DIR" ]]; then
    CONFIG_STATE="unexpected"
  elif [[ -d "$CONFIG_DIR" ]]; then
    CONFIG_STATE="present"
  elif [[ -e "$CONFIG_DIR" ]]; then
    CONFIG_STATE="unexpected"
  fi
}

#
# Run docker as the same user the installer used (root, under sudo).
# On macOS that can occasionally fail even though Docker Desktop is
# running fine for the normal user, because root's docker command
# talks to Docker Desktop through a socket that Docker Desktop may not
# have exposed to root. If that happens, retry as the person who ran
# sudo. Never starts Docker: an uninstaller that launches a large
# application as a side effect would be a surprise.
#
docker_cmd() {
  if [[ -n "$DOCKER_RUN_AS" ]]; then
    sudo -u "$DOCKER_RUN_AS" docker "$@"
  else
    docker "$@"
  fi
}

inspect_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    DOCKER_STATE="missing"
    return
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_STATE="ready"
    return
  fi

  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] &&
    command -v sudo >/dev/null 2>&1 &&
    sudo -u "$SUDO_USER" docker info >/dev/null 2>&1; then
    DOCKER_RUN_AS="$SUDO_USER"
    DOCKER_STATE="ready"
    return
  fi

  DOCKER_STATE="not_running"
}

#
# Find every local image from the OPM Flow repository, not just the
# one currently pinned in the config. Each 'opmflow upgrade' pulls a
# new image and leaves the previous one behind, so over time there can
# be several. Every line is checked against a strict pattern before it
# is ever passed to 'docker rmi'. Untagged leftovers (<none>) fail the
# pattern and are skipped.
#
find_images() {
  local raw
  raw="$(docker_cmd image ls --format '{{.Repository}}:{{.Tag}}' "$IMAGE_REPOSITORY" 2>/dev/null || true)"

  local line
  while IFS= read -r line; do
    [[ "$line" =~ ^openporousmedia/opmreleases:[A-Za-z0-9_.-]+$ ]] || continue
    IMAGES+="${line}"$'\n'
  done <<< "$(printf '%s\n' "$raw" | sort -u)"
}

inspect_system() {
  inspect_files

  if [[ "$KEEP_IMAGES" == "true" ]]; then
    return
  fi

  inspect_docker

  if [[ "$DOCKER_STATE" == "ready" ]]; then
    find_images
  fi
}

nothing_to_remove() {
  [[ "$WRAPPER_STATE" != "ours" ]] || return 1
  [[ "$LINK_STATE" != "ours" ]] || return 1
  [[ "$CONFIG_STATE" != "present" ]] || return 1
  [[ -z "$IMAGES" ]]
}

plan() {
  printf '[opm-flow]     %-9s %s\n' "$1" "$2"
}

print_plan() {
  log "OPM Flow uninstaller"
  log ""
  log "Found on this computer:"
  log ""

  case "$WRAPPER_STATE" in
    ours)    plan "remove" "${WRAPPER_PATH}   (the OPM Flow command)" ;;
    foreign) plan "keep" "${WRAPPER_PATH}   (not created by the OPM Flow installer)" ;;
  esac

  case "$LINK_STATE" in
    ours)    plan "remove" "${LINK_PATH}   (shortcut to the command above)" ;;
    foreign) plan "keep" "${LINK_PATH}   (not the OPM Flow command, may be a different program)" ;;
  esac

  case "$CONFIG_STATE" in
    present)    plan "remove" "${CONFIG_DIR}   (saved version and variant settings)" ;;
    unexpected) plan "keep" "${CONFIG_DIR}   (not a normal folder, not touching it)" ;;
  esac

  if [[ -n "$IMAGES" ]]; then
    local ref
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      plan "remove" "Docker image ${ref}"
    done <<< "$IMAGES"
  fi

  if [[ "$KEEP_IMAGES" == "true" ]]; then
    plan "keep" "Docker images   (because --keep-images was given)"
  elif [[ "$DOCKER_STATE" == "not_running" ]]; then
    plan "skip" "Docker images   (Docker is installed but not running)"
  elif [[ "$DOCKER_STATE" == "missing" ]]; then
    plan "skip" "Docker images   (Docker was not found)"
  fi

  log ""
  log "Not touched, on purpose:"
  log "    - Docker itself"
  log "    - your simulation files (.DATA files and results)"
  log ""
}

#
# Asks on the real terminal (/dev/tty) rather than stdin, so the
# question still works if this script was started through a pipe. If
# there is no terminal at all (cron, CI), it refuses to guess and asks
# for --yes instead of silently proceeding or silently doing nothing.
#
confirm() {
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi

  if ! : </dev/tty 2>/dev/null; then
    die "Cannot ask for confirmation because there is no terminal.

    Re-run with --yes to proceed without being asked, or use --dry-run
    to just preview."
  fi

  local answer
  read -r -p "[opm-flow] Remove the items marked 'remove' above? [y/N] " answer </dev/tty

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

remove_file() {
  local path="$1"
  local description="$2"

  if rm -f "$path"; then
    note_done "${description}  (${path})"
  else
    warn "Could not remove ${path}"
    note_left "${description}  (${path}), could not be removed"
    note_failure
  fi
}

remove_config() {
  rm -f "$CONFIG_FILE" ||
    {
      warn "Could not remove ${CONFIG_FILE}"
      note_left "Saved settings (${CONFIG_FILE}), could not be removed"
      note_failure
      return
    }

  #
  # rmdir, never 'rm -rf': only an empty folder is removed, so anything
  # unexpected that someone put in here is kept rather than destroyed.
  #
  if rmdir "$CONFIG_DIR" 2>/dev/null; then
    note_done "Saved settings  (${CONFIG_DIR})"
  else
    warn "${CONFIG_DIR} still has other files in it, so the folder was kept."
    note_left "${CONFIG_DIR}  (the settings file was removed, but the folder has other files in it)"
  fi
}

#
# Never uses 'docker rmi --force'. If an image is still in use (for
# example a simulation is running right now), Docker refuses, and we
# report that instead of ripping the image out from under a running
# job.
#
remove_images() {
  local ref out

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue

    if out="$(docker_cmd rmi "$ref" 2>&1)"; then
      note_done "Docker image ${ref}"
    else
      warn "Could not remove Docker image ${ref}:"
      printf '    %s\n' "$out" >&2
      note_left "Docker image ${ref}, Docker refused to remove it (is a simulation still running?)"
      note_failure
    fi
  done <<< "$IMAGES"
}

execute() {
  if [[ "$LINK_STATE" == "ours" ]]; then
    remove_file "$LINK_PATH" "The 'flow' command"
  elif [[ "$LINK_STATE" == "foreign" ]]; then
    note_left "${LINK_PATH}  (not created by the OPM Flow installer, left alone)"
  fi

  if [[ "$WRAPPER_STATE" == "ours" ]]; then
    remove_file "$WRAPPER_PATH" "The 'opmflow' command"
  elif [[ "$WRAPPER_STATE" == "foreign" ]]; then
    note_left "${WRAPPER_PATH}  (not created by the OPM Flow installer, left alone)"
  fi

  if [[ "$CONFIG_STATE" == "present" ]]; then
    remove_config
  elif [[ "$CONFIG_STATE" == "unexpected" ]]; then
    note_left "${CONFIG_DIR}  (not a normal folder, left alone)"
  fi

  if [[ -n "$IMAGES" ]]; then
    remove_images
  fi

  if [[ "$KEEP_IMAGES" == "true" ]]; then
    note_left "Docker images  (kept because --keep-images was given)"
  elif [[ "$DOCKER_STATE" == "not_running" ]]; then
    note_left "Docker images  (Docker was not running, so they could not be checked.
                  Start Docker, then run this uninstaller again.)"
  elif [[ "$DOCKER_STATE" == "missing" ]]; then
    note_left "Docker images  (Docker was not found, so there was nothing to check)"
  fi
}

print_summary() {
  log ""

  if [[ -n "$DONE" ]]; then
    log "Removed:"
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      log "    - ${line}"
    done <<< "$DONE"
    log ""
  fi

  if [[ -n "$LEFT" ]]; then
    log "Left in place:"
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      log "    - ${line}"
    done <<< "$LEFT"
    log ""
  fi

  log "Docker itself and your simulation files were not touched."
  log ""
  log "If this terminal still finds 'flow' after this, that is only the"
  log "shell remembering the old location. Run 'hash -r' or open a new"
  log "terminal window."

  if [[ $FAILURES -gt 0 ]]; then
    log ""
    warn "Finished, but ${FAILURES} item(s) could not be removed. See the messages above."
    exit 1
  fi

  log ""
  log "OPM Flow uninstall completed."
}

main() {
  parse_arguments "$@"

  if [[ "$DRY_RUN" != "true" ]]; then
    require_root
  fi

  inspect_system

  if nothing_to_remove; then
    print_plan

    if [[ "$DOCKER_STATE" == "not_running" ]]; then
      log "The OPM Flow commands and settings are already gone, but Docker is"
      log "not running, so any downloaded OPM Flow images could not be checked."
      log "Start Docker, then run this uninstaller again to clean those up."
    else
      log "Nothing to remove. OPM Flow does not appear to be installed."
    fi

    exit 0
  fi

  print_plan

  if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run: nothing was changed."
    log "To really uninstall, run:"
    log ""
    log "    sudo ./opmflow-uninstall.sh"
    exit 0
  fi

  confirm
  execute
  print_summary
}

main "$@"
