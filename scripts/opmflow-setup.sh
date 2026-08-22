#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR="/usr/local/bin"
readonly CONFIG_DIR="/etc/opm-flow"
readonly CONFIG_FILE="${CONFIG_DIR}/config"

readonly IMAGE_REPOSITORY="openporousmedia/opmreleases"

readonly DEFAULT_VERSION="latest"
readonly DEFAULT_VARIANT="auto"

OPM_FLOW_VERSION="$DEFAULT_VERSION"
OPM_FLOW_VARIANT="$DEFAULT_VARIANT"

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

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This installer must be run with sudo:

    sudo ./setup.sh"
  fi
}

validate_version() {
  local version="$1"

  if [[ "$version" == "latest" ]]; then
    return 0
  fi

  if [[ ! "$version" =~ ^[0-9]{4}\.[0-9]{2}$ ]]; then
    die "Invalid OPM Flow version: ${version}

    Expected:

        latest
        YYYY.MM

    Examples:

        latest
        2026.04"
  fi
}

validate_variant() {
  local variant="$1"

  case "$variant" in
    auto|none|amd|amd64|arm64|nvidia)
    ;;

    *)
      die "Unsupported OPM Flow variant: ${variant}

      Supported variants:

          auto
          none
          amd
          amd64
          arm64
          nvidia"
    ;;
  esac
}

detect_host_variant() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf '%s\n' "amd64"
    ;;

    aarch64|arm64)
      printf '%s\n' "arm64"
    ;;

    *)
      die "Unable to determine an automatic OPM Flow variant from:

          $(uname -m)

      Specify one explicitly:

          --variant amd64
          --variant amd
          --variant arm64
          --variant nvidia
          --variant none"
    ;;
  esac
}

image_for_variant() {
  local version="$1"
  local variant="$2"

  if [[ "$variant" == "none" ]]; then
    printf '%s:%s\n' \
      "$IMAGE_REPOSITORY" \
      "$version"
    return
  fi

  printf '%s:%s_%s\n' \
    "$IMAGE_REPOSITORY" \
    "$version" \
    "$variant"
}

image_exists_locally() {
  local image="$1"

  docker image inspect "$image" >/dev/null 2>&1
}

image_exists_remotely() {
  local image="$1"

  #
  # docker manifest inspect asks the registry whether a tag
  # exists and returns its manifest, without downloading any
  # image layers.
  #
  DOCKER_CLI_EXPERIMENTAL=enabled \
    docker manifest inspect "$image" >/dev/null 2>&1
}

try_resolve_image() {
  local image="$1"

  log "Checking ${image}..." >&2

  image_exists_locally "$image" || image_exists_remotely "$image"
}

pull_image() {
  local image="$1"

  if image_exists_locally "$image"; then
    log "Image already present locally, skipping pull: ${image}"
    return 0
  fi

  log "Pulling ${image}..."

  docker pull "$image" ||
    die "Unable to pull Docker image:

    ${image}"
}

resolve_image() {
  local version="$1"
  local variant="$2"

  validate_version "$version"
  validate_variant "$variant"

  #
  # Explicitly request the unsuffixed image.
  #
  if [[ "$variant" == "none" ]]; then
    local image
    image="${IMAGE_REPOSITORY}:${version}"

    if ! try_resolve_image "$image"; then
      die "OPM Flow image does not exist:

      ${image}"
    fi

    printf '%s\n' "$image"
    return
  fi

  #
  # Explicit variant.
  #
  # Never silently fall back to another variant.
  #
  if [[ "$variant" != "auto" ]]; then
    local image
    image="$(image_for_variant "$version" "$variant")"

    if ! try_resolve_image "$image"; then
      die "OPM Flow image does not exist:

          ${image}

      Requested variant:

          ${variant}

      Use --variant auto to allow automatic resolution."
    fi

    printf '%s\n' "$image"
    return
  fi

  #
  # Automatic resolution.
  #
  local host_variant
  host_variant="$(detect_host_variant)"

  log "Automatic variant selected: ${host_variant}" >&2

  #
  # First try the modern platform-specific tag.
  #
  local candidate
  candidate="$(image_for_variant "$version" "$host_variant")"

  if try_resolve_image "$candidate"; then
    printf '%s\n' "$candidate"
    return
  fi

  #
  # Older releases may not have a variant suffix.
  #
  local fallback
  fallback="${IMAGE_REPOSITORY}:${version}"

  log "Variant-specific image unavailable; trying unsuffixed image." >&2

  if try_resolve_image "$fallback"; then
    printf '%s\n' "$fallback"
    return
  fi

  die "Unable to find an OPM Flow image for version ${version}.

  Tried:

      ${candidate}
      ${fallback}

  Specify an explicit variant if appropriate."
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker found: $(docker --version)"
    return
  fi

  log "Docker is not installed. Installing..."

  if command -v apt-get >/dev/null 2>&1; then
    # Debian, Ubuntu, and derivatives.
    apt-get update
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings

    # shellcheck disable=SC1091
    . /etc/os-release

    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
      -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
      "$(dpkg --print-architecture)" \
      "$ID" \
      "${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo stable)}" \
      > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io

  elif command -v dnf >/dev/null 2>&1; then
    # Fedora, and RHEL/CentOS Stream with the moby packages.
    dnf install -y moby-engine docker-cli

  elif command -v yum >/dev/null 2>&1; then
    # Older RHEL/CentOS, Amazon Linux.
    yum install -y moby-engine docker-cli 2>/dev/null ||
      yum install -y docker

  elif command -v pacman >/dev/null 2>&1; then
    # Arch, Manjaro.
    pacman -Sy --noconfirm docker

  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE.
    zypper --non-interactive install docker

  elif command -v curl >/dev/null 2>&1; then
    warn "No supported package manager detected; using Docker's official install script."

    curl -fsSL https://get.docker.com | sh

  else
    die "Unable to install Docker automatically on this platform.

    Install Docker manually and run this installer again."
  fi

  systemctl enable --now docker ||
    die "Docker was installed, but the systemd service could not be started.

    If this host does not use systemd, start the Docker daemon manually
    and run this installer again."
}

verify_docker() {
  command -v docker >/dev/null 2>&1 ||
    die "Docker installation failed."

  if ! systemctl is-active --quiet docker; then
    log "Starting Docker service..."
    systemctl enable --now docker
  fi

  if ! docker info >/dev/null 2>&1; then
    die "Docker is installed but cannot be accessed.

    Check:

        sudo systemctl status docker"
  fi
}

run_flow_version() {
  local image="$1"

  docker run --rm \
    "$image" \
    flow --version
}

extract_version() {
  local output="$1"

  if [[ "$output" =~ ([0-9]{4}\.[0-9]{2}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

resolve_latest_version_number() {
  command -v curl >/dev/null 2>&1 || return 1

  local url="https://hub.docker.com/v2/repositories/${IMAGE_REPOSITORY}/tags?page_size=100&ordering=-last_updated"
  local response

  response="$(curl -fsSL "$url" 2>/dev/null)" || return 1

  printf '%s\n' "$response" |
    grep -oE '"name":\s*"[0-9]{4}\.[0-9]{2}(_[A-Za-z0-9]+)?"' |
    grep -oE '[0-9]{4}\.[0-9]{2}' |
    sort -ru |
    head -n1
}

write_config() {
  local version="$1"
  local variant="$2"
  local image="$3"

  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<EOF
OPM_FLOW_VERSION=${version}
OPM_FLOW_VARIANT=${variant}
OPM_FLOW_IMAGE=${image}
EOF

  chmod 0644 "$CONFIG_FILE"
}

install_wrapper() {
  cat > "${INSTALL_DIR}/opmflow" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_FILE="/etc/opm-flow/config"
readonly IMAGE_REPOSITORY="openporousmedia/opmreleases"

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

require_docker() {
    command -v docker >/dev/null 2>&1 ||
        die "Docker is not installed."
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This operation requires root privileges.

Run it with sudo."
    fi
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "OPM Flow is not configured.

Run the installer first:

    sudo ./setup.sh"
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${OPM_FLOW_VERSION:?Missing OPM_FLOW_VERSION in ${CONFIG_FILE}}"
    : "${OPM_FLOW_VARIANT:?Missing OPM_FLOW_VARIANT in ${CONFIG_FILE}}"
    : "${OPM_FLOW_IMAGE:?Missing OPM_FLOW_IMAGE in ${CONFIG_FILE}}"
}

validate_version() {
    local version="$1"

    if [[ ! "$version" =~ ^[0-9]{4}\.[0-9]{2}$ ]]; then
        die "Invalid OPM Flow version: ${version}"
    fi
}

validate_variant() {
    local variant="$1"

    case "$variant" in
        auto|none|amd|amd64|arm64|nvidia)
            ;;

        *)
            die "Unsupported OPM Flow variant: ${variant}"
            ;;
    esac
}

image_for_variant() {
    local version="$1"
    local variant="$2"

    if [[ "$variant" == "none" ]]; then
        printf '%s:%s\n' \
            "$IMAGE_REPOSITORY" \
            "$version"
        return
    fi

    printf '%s:%s_%s\n' \
        "$IMAGE_REPOSITORY" \
        "$version" \
        "$variant"
}

image_exists_locally() {
    local image="$1"

    docker image inspect "$image" >/dev/null 2>&1
}

image_exists_remotely() {
    local image="$1"

    DOCKER_CLI_EXPERIMENTAL=enabled \
        docker manifest inspect "$image" >/dev/null 2>&1
}

try_resolve_image() {
    local image="$1"

    log "Checking ${image}..."

    image_exists_locally "$image" || image_exists_remotely "$image"
}

pull_image() {
    local image="$1"

    if image_exists_locally "$image"; then
        log "Image already present locally, skipping pull: ${image}"
        return 0
    fi

    log "Pulling ${image}..."

    docker pull "$image" ||
        die "Unable to pull:

    ${image}"
}

ensure_image() {
    if image_exists_locally "$OPM_FLOW_IMAGE"; then
        return
    fi

    log "Configured OPM Flow image is not available locally."

    pull_image "$OPM_FLOW_IMAGE"
}

run_flow_version() {
    local image="$1"

    docker run --rm \
        "$image" \
        flow --version
}

extract_version() {
    local output="$1"

    if [[ "$output" =~ ([0-9]{4}\.[0-9]{2}) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

resolve_latest_version_number() {
    command -v curl >/dev/null 2>&1 || return 1

    local url="https://hub.docker.com/v2/repositories/${IMAGE_REPOSITORY}/tags?page_size=100&ordering=-last_updated"
    local response

    response="$(curl -fsSL "$url" 2>/dev/null)" || return 1

    printf '%s\n' "$response" |
        grep -oE '"name":\s*"[0-9]{4}\.[0-9]{2}(_[A-Za-z0-9]+)?"' |
        grep -oE '[0-9]{4}\.[0-9]{2}' |
        sort -ru |
        head -n1
}

show_version() {
    ensure_image

    run_flow_version "$OPM_FLOW_IMAGE"
}

show_image() {
    printf '%s\n' "$OPM_FLOW_IMAGE"
}

show_variant() {
    printf '%s\n' "$OPM_FLOW_VARIANT"
}

show_config() {
    cat "$CONFIG_FILE"
}

upgrade_to_version() {
    local version="$1"

    validate_version "$version"

    #
    # The wrapper intentionally does not perform automatic tag
    # discovery here. The installer stores the resolved image.
    #
    # For an explicit upgrade version, resolve the configured
    # variant in the same way as setup.
    #
    local image

    if [[ "$OPM_FLOW_VARIANT" == "none" ]]; then
        image="${IMAGE_REPOSITORY}:${version}"

    elif [[ "$OPM_FLOW_VARIANT" != "auto" ]]; then
        image="${IMAGE_REPOSITORY}:${version}_${OPM_FLOW_VARIANT}"

    else
        local host_variant

        case "$(uname -m)" in
            x86_64|amd64)
                host_variant="amd64"
                ;;

            aarch64|arm64)
                host_variant="arm64"
                ;;

            *)
                die "Unable to determine an automatic OPM Flow variant.

Specify a variant explicitly."
                ;;
        esac

        local candidate
        candidate="${IMAGE_REPOSITORY}:${version}_${host_variant}"

        if try_resolve_image "$candidate"; then
            image="$candidate"
        else
            image="${IMAGE_REPOSITORY}:${version}"

            if ! try_resolve_image "$image"; then
                die "Unable to find an OPM Flow image for:

    ${version}

Tried:

    ${candidate}
    ${image}"
            fi
        fi
    fi

    pull_image "$image"

    write_config \
        "$version" \
        "$OPM_FLOW_VARIANT" \
        "$image"

    log "OPM Flow ${version} is now pinned."
    log "Image: ${image}"
}

upgrade_to_latest() {
    log "Determining latest OPM Flow version..."

    local version

    if version="$(resolve_latest_version_number)" && [[ -n "$version" ]]; then
        log "Latest OPM Flow release (from registry API): ${version}"
        upgrade_to_version "$version"
        return
    fi

    warn "Could not reach the registry API; falling back to pulling :latest to read its version."

    local latest_image="${IMAGE_REPOSITORY}:latest"

    pull_image "$latest_image"

    local output

    if ! output="$(run_flow_version "$latest_image" 2>&1)"; then
        printf '%s\n' "$output" >&2

        die "Unable to determine the latest OPM Flow version."
    fi

    if ! version="$(extract_version "$output")"; then
        die "Unable to determine the OPM Flow version from:

${output}"
    fi

    log "Latest OPM Flow release: ${version}"

    upgrade_to_version "$version"
}

upgrade() {
    require_root

    case "$#" in
        0)
            upgrade_to_latest
            ;;

        1)
            upgrade_to_version "$1"
            ;;

        *)
            die "Usage:

    sudo opmflow upgrade
    sudo opmflow upgrade VERSION"
            ;;
    esac
}

configure_variant() {
    require_root

    if [[ $# -ne 1 ]]; then
        die "Usage:

    sudo opmflow configure --variant VARIANT"
    fi

    local variant="$1"

    validate_variant "$variant"

    local version="$OPM_FLOW_VERSION"
    local image

    if [[ "$variant" == "none" ]]; then
        image="${IMAGE_REPOSITORY}:${version}"

    elif [[ "$variant" != "auto" ]]; then
        image="${IMAGE_REPOSITORY}:${version}_${variant}"

    else
        case "$(uname -m)" in
            x86_64|amd64)
                variant="auto"
                image="${IMAGE_REPOSITORY}:${version}_amd64"
                ;;

            aarch64|arm64)
                variant="auto"
                image="${IMAGE_REPOSITORY}:${version}_arm64"
                ;;

            *)
                die "Unable to determine an automatic variant."
                ;;
        esac

        log "Trying ${image}..."

        if ! docker pull "$image" >/dev/null 2>&1; then
            image="${IMAGE_REPOSITORY}:${version}"

            log "Falling back to ${image}..."

            docker pull "$image" ||
                die "Unable to resolve automatic variant."
        fi
    fi

    if [[ "$variant" != "auto" ]]; then
        pull_image "$image"
    fi

    write_config \
        "$version" \
        "$variant" \
        "$image"

    log "OPM Flow variant changed to ${variant}."
    log "Image: ${image}"
}

show_help() {
    cat <<EOF
OPM Flow Docker wrapper

Run OPM Flow:

    flow SPE1.DATA
    opmflow SPE1.DATA

All arguments not listed below are passed directly to OPM Flow.

Management commands:

    opmflow version
        Display the configured OPM Flow version.

    opmflow image
        Display the configured Docker image.

    opmflow variant
        Display the configured variant.

    opmflow config
        Display the current configuration.

    sudo opmflow upgrade
        Resolve the latest release and pin it.

    sudo opmflow upgrade VERSION
        Resolve and pin VERSION.

    sudo opmflow configure --variant VARIANT
        Change the configured variant.

Variants:

    auto
        Automatically choose the host-compatible image.
        Falls back to the unsuffixed image for older releases.

    amd64
        Use VERSION_amd64.

    amd
        Use VERSION_amd.

    arm64
        Use VERSION_arm64.

    nvidia
        Use VERSION_nvidia.

    none
        Use VERSION without a suffix.

Examples:

    flow SPE1.DATA
    flow --help
    flow --version

    opmflow version
    opmflow image
    opmflow variant
    opmflow config

    sudo opmflow upgrade
    sudo opmflow upgrade 2026.04

    sudo opmflow configure --variant amd64
    sudo opmflow configure --variant nvidia
    sudo opmflow configure --variant none

Current configuration:

    Version: ${OPM_FLOW_VERSION}
    Variant: ${OPM_FLOW_VARIANT}
    Image:   ${OPM_FLOW_IMAGE}
EOF
}

run_flow() {
    ensure_image

    local workdir
    workdir="$(pwd -P)"

    local mount_spec="${workdir}:/simulation"

    #
    # On SELinux-enforcing hosts (Fedora, RHEL, CentOS, ...) a
    # plain bind mount is denied inside the container's confined
    # policy unless it's relabeled for shared access with ':z'.
    #
    if command -v getenforce >/dev/null 2>&1 &&
        [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        mount_spec="${mount_spec}:z"
    fi

    exec docker run --rm \
        --init \
        --user "$(id -u):$(id -g)" \
        --workdir /simulation \
        --volume "$mount_spec" \
        "$OPM_FLOW_IMAGE" \
        flow "$@"
}

main() {
    require_docker
    load_config

    case "${1:-}" in

        upgrade)
            shift
            upgrade "$@"
            ;;

        configure)
            shift

            if [[ "${1:-}" == "--variant" ]]; then
                shift
                configure_variant "$@"
            else
                die "Usage:

    sudo opmflow configure --variant VARIANT"
            fi
            ;;

        version|--version)
            show_version
            ;;

        image)
            show_image
            ;;

        variant)
            show_variant
            ;;

        config)
            show_config
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            run_flow "$@"
            ;;
    esac
}

main "$@"
WRAPPER

  chmod 0755 "${INSTALL_DIR}/opmflow"

  ln -sf "${INSTALL_DIR}/opmflow" "${INSTALL_DIR}/flow"
}

setup_from_latest() {
  log "Determining latest OPM Flow version..."

  local version

  if version="$(resolve_latest_version_number)" && [[ -n "$version" ]]; then
    log "Latest OPM Flow release (from registry API): ${version}"
    OPM_FLOW_VERSION="$version"
    return
  fi

  warn "Could not reach the registry API; falling back to pulling :latest to read its version."

  local latest_image="${IMAGE_REPOSITORY}:latest"

  pull_image "$latest_image"

  local output

  if ! output="$(run_flow_version "$latest_image" 2>&1)"; then
    printf '%s\n' "$output" >&2

    die "Unable to execute Flow from:

    ${latest_image}"
  fi

  log "Flow reports: ${output}"

  if ! version="$(extract_version "$output")"; then
    die "Unable to determine the OPM Flow version from:

    ${output}"
  fi

  log "Resolved latest release: ${version}"

  OPM_FLOW_VERSION="$version"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in

      --version)
        [[ $# -ge 2 ]] ||
          die "--version requires a value."

        OPM_FLOW_VERSION="$2"
        shift 2
      ;;

      --version=*)
        OPM_FLOW_VERSION="${1#*=}"
        shift
      ;;

      --variant)
        [[ $# -ge 2 ]] ||
          die "--variant requires a value."

        OPM_FLOW_VARIANT="$2"
        shift 2
      ;;

      --variant=*)
        OPM_FLOW_VARIANT="${1#*=}"
        shift
      ;;

      -h|--help)
        cat <<EOF
OPM Flow Docker installer

Usage:

    sudo ./setup.sh
    sudo ./setup.sh --version latest
    sudo ./setup.sh --version 2026.04

    sudo ./setup.sh --variant auto
    sudo ./setup.sh --variant amd64
    sudo ./setup.sh --variant amd
    sudo ./setup.sh --variant arm64
    sudo ./setup.sh --variant nvidia
    sudo ./setup.sh --variant none

    sudo ./setup.sh --version latest --variant nvidia
    sudo ./setup.sh --version 2015.06 --variant none

Options:

    --version VERSION

        OPM Flow version.

        Supported:

            latest
            YYYY.MM

        Default:

            latest

    --variant VARIANT

        OPM Flow image variant/suffix.

        Supported:

            auto
            none
            amd64
            amd
            arm64
            nvidia

        Default:

            auto

        auto:

            x86_64 → try VERSION_amd64
                    then VERSION

            arm64 → try VERSION_arm64
                    then VERSION

        none explicitly selects the unsuffixed image.

Examples:

    sudo ./setup.sh

    sudo ./setup.sh --version latest

    sudo ./setup.sh --version latest --variant auto

    sudo ./setup.sh --version latest --variant nvidia

    sudo ./setup.sh --version 2026.04 --variant amd64

    sudo ./setup.sh --version 2026.04 --variant amd

    sudo ./setup.sh --version 2015.06 --variant none
EOF
        exit 0
      ;;

      *)
        die "Unknown setup option: $1

        Run:

            ./setup.sh --help"
      ;;
    esac
  done

  validate_version "$OPM_FLOW_VERSION"
  validate_variant "$OPM_FLOW_VARIANT"
}

verify_flow() {
  local image="$1"

  log "Verifying OPM Flow..."

  local output

  if ! output="$(docker run --rm "$image" flow --version 2>&1)"; then
    printf '%s\n' "$output" >&2

    die "The OPM Flow image was pulled, but Flow could not be executed."
  fi

  log "Flow reports:"
  printf '%s\n' "$output"
}

main() {
  require_root

  parse_arguments "$@"

  install_docker
  verify_docker

  log "OPM Flow configuration:"
  log "    Requested version: ${OPM_FLOW_VERSION}"
  log "    Requested variant: ${OPM_FLOW_VARIANT}"

  if [[ "$OPM_FLOW_VERSION" == "latest" ]]; then
    setup_from_latest
  fi

  local image
  image="$(resolve_image \
    "$OPM_FLOW_VERSION" \
    "$OPM_FLOW_VARIANT")"

  log "Resolved image: ${image}"

  pull_image "$image"

  write_config \
    "$OPM_FLOW_VERSION" \
    "$OPM_FLOW_VARIANT" \
    "$image"

  install_wrapper

  verify_flow "$image"

  log ""
  log "OPM Flow installation completed."
  log ""
  log "Pinned configuration:"
  log "    Version: ${OPM_FLOW_VERSION}"
  log "    Variant: ${OPM_FLOW_VARIANT}"
  log "    Image:   ${image}"
  log ""
  log "Run:"
  log "    flow SPE1.DATA"
  log "    opmflow SPE1.DATA"
  log ""
  log "Management:"
  log "    opmflow version"
  log "    opmflow image"
  log "    opmflow variant"
  log "    opmflow config"
  log "    sudo opmflow upgrade"
  log "    sudo opmflow upgrade VERSION"
  log "    sudo opmflow configure --variant VARIANT"
}

main "$@"
