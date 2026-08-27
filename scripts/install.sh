#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# AdBot Installer
# ============================================================

REPO="sorabhyadavpalothar/adbot"
VERSION="v3.1.3"

BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
ENV_FILE="${SCRIPT_DIR}/.env"

TMP_DIR=""

# ============================================================
# Colors
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Helpers
# ============================================================

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

die() {
    error "$1"
    cleanup
    exit 1
}

cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}

trap cleanup EXIT
trap 'die "Installation interrupted."' INT TERM

# ============================================================
# Banner
# ============================================================

banner() {
    echo
    echo "=============================================="
    echo "              AdBot Installer"
    echo "=============================================="
    echo
    echo "Repository : ${REPO}"
    echo "Version    : ${VERSION}"
    echo
}

# ============================================================
# Command check
# ============================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# Detect Host OS
# ============================================================

detect_host_os() {

    case "$(uname -s)" in

        Linux*)
            HOST_OS="linux"
            ;;

        Darwin*)
            HOST_OS="darwin"
            ;;

        MINGW*|MSYS*|CYGWIN*)
            HOST_OS="windows"
            ;;

        *)
            die "Unsupported host OS: $(uname -s)"
            ;;

    esac

    info "Host OS: ${HOST_OS}"
}

# ============================================================
# Detect Host Architecture
# ============================================================

detect_host_arch() {

    case "$(uname -m)" in

        x86_64|amd64)
            HOST_ARCH="amd64"
            ;;

        aarch64|arm64)
            HOST_ARCH="arm64"
            ;;

        *)
            die "Unsupported architecture: $(uname -m)"
            ;;

    esac

    info "Host architecture: ${HOST_ARCH}"
}

# ============================================================
# Detect Docker
# ============================================================

detect_docker() {

    DOCKER_AVAILABLE="false"

    if command_exists docker; then
        DOCKER_AVAILABLE="true"
        success "Docker detected"

        DOCKER_VERSION="$(docker --version 2>/dev/null || true)"

        if [[ -n "${DOCKER_VERSION}" ]]; then
            info "${DOCKER_VERSION}"
        fi

    else
        warn "Docker is not installed"
    fi
}

# ============================================================
# Detect Docker Server OS / Arch
# ============================================================

detect_docker_platform() {

    DOCKER_OS=""
    DOCKER_ARCH=""

    if [[ "${DOCKER_AVAILABLE}" != "true" ]]; then
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        warn "Docker daemon is not running"

        return
    fi

    PLATFORM="$(docker version \
        --format '{{.Server.Os}} {{.Server.Arch}}' \
        2>/dev/null || true)"

    if [[ -z "${PLATFORM}" ]]; then
        warn "Unable to detect Docker platform"
        return
    fi

    DOCKER_OS="$(echo "${PLATFORM}" | awk '{print $1}')"
    DOCKER_ARCH="$(echo "${PLATFORM}" | awk '{print $2}')"

    case "${DOCKER_ARCH}" in
        x86_64)
            DOCKER_ARCH="amd64"
            ;;
        aarch64)
            DOCKER_ARCH="arm64"
            ;;
    esac

    success "Docker OS: ${DOCKER_OS}"
    success "Docker architecture: ${DOCKER_ARCH}"
}

# ============================================================
# Select Release Target
# ============================================================

select_target() {

    # If Docker is available and running,
    # Docker platform becomes the primary target.

    if [[ -n "${DOCKER_OS}" && -n "${DOCKER_ARCH}" ]]; then

        TARGET_OS="${DOCKER_OS}"
        TARGET_ARCH="${DOCKER_ARCH}"

        info "Using Docker platform as release target"

    else

        TARGET_OS="${HOST_OS}"
        TARGET_ARCH="${HOST_ARCH}"

        info "Using host platform as release target"

    fi

    case "${TARGET_OS}" in
        linux|darwin|windows)
            ;;
        *)
            die "Unsupported target OS: ${TARGET_OS}"
            ;;
    esac

    case "${TARGET_ARCH}" in
        amd64|arm64)
            ;;
        *)
            die "Unsupported target architecture: ${TARGET_ARCH}"
            ;;
    esac

    RELEASE_ASSET="adbot-${TARGET_OS}-${TARGET_ARCH}"

    if [[ "${TARGET_OS}" == "windows" ]]; then
        RELEASE_ASSET="${RELEASE_ASSET}.exe"
    fi

    info "Selected asset: ${RELEASE_ASSET}"
}

# ============================================================
# Check required tools
# ============================================================

check_tools() {

    if ! command_exists curl; then
        die "curl is required."
    fi

    if ! command_exists sha256sum; then

        if ! command_exists shasum; then
            die "sha256sum or shasum is required."
        fi

    fi

    success "Required tools available"
}

# ============================================================
# Create directories
# ============================================================

create_directories() {

    mkdir -p "${DIST_DIR}"

    success "dist/ directory ready"
}

# ============================================================
# Download
# ============================================================

download_release() {

    TMP_DIR="$(mktemp -d)"

    BINARY_TMP="${TMP_DIR}/${RELEASE_ASSET}"
    CHECKSUM_TMP="${TMP_DIR}/SHA256SUMS"

    info "Downloading ${RELEASE_ASSET}"

    curl \
        --fail \
        --location \
        --progress-bar \
        --retry 3 \
        --retry-delay 2 \
        "${BASE_URL}/${RELEASE_ASSET}" \
        -o "${BINARY_TMP}" \
        || die "Failed to download ${RELEASE_ASSET}"

    success "Binary downloaded"

    info "Downloading SHA256SUMS"

    curl \
        --fail \
        --location \
        --progress-bar \
        --retry 3 \
        --retry-delay 2 \
        "${BASE_URL}/SHA256SUMS" \
        -o "${CHECKSUM_TMP}" \
        || die "Failed to download SHA256SUMS"

    success "SHA256SUMS downloaded"
}

# ============================================================
# SHA256
# ============================================================

calculate_sha256() {

    local file="$1"

    if command_exists sha256sum; then

        sha256sum "${file}" | awk '{print $1}'

    else

        shasum -a 256 "${file}" | awk '{print $1}'

    fi
}

# ============================================================
# Verify checksum
# ============================================================

verify_checksum() {

    info "Verifying SHA256..."

    EXPECTED_HASH="$(
        awk -v file="${RELEASE_ASSET}" '
            $2 == file || $2 == "*" file {
                print $1
                exit
            }
        ' "${CHECKSUM_TMP}"
    )"

    if [[ -z "${EXPECTED_HASH}" ]]; then
        die "Checksum for ${RELEASE_ASSET} not found."
    fi

    ACTUAL_HASH="$(calculate_sha256 "${BINARY_TMP}")"

    if [[ "${ACTUAL_HASH}" != "${EXPECTED_HASH}" ]]; then

        echo
        error "SHA256 verification failed"
        echo
        echo "Expected:"
        echo "${EXPECTED_HASH}"
        echo
        echo "Actual:"
        echo "${ACTUAL_HASH}"

        die "Binary checksum mismatch."

    fi

    success "SHA256 verification passed"
}

# ============================================================
# Install binary
# ============================================================

install_binary() {

    if [[ "${TARGET_OS}" == "windows" ]]; then

        BINARY_NAME="adbot.exe"

    else

        BINARY_NAME="adbot"

    fi

    DESTINATION="${DIST_DIR}/${BINARY_NAME}"

    info "Installing binary as ${DESTINATION}"

    cp "${BINARY_TMP}" "${DESTINATION}"

    chmod +x "${DESTINATION}" 2>/dev/null || true

    success "Created ${DESTINATION}"
}

# ============================================================
# Generate encryption key
# ============================================================

generate_encryption_key() {

    if command_exists openssl; then

        openssl rand -base64 32 |
            tr '+/' '-_' |
            tr -d '='

    else

        if [[ -r /dev/urandom ]]; then

            head -c 32 /dev/urandom |
                base64 |
                tr '+/' '-_' |
                tr -d '='

        else

            die "openssl or /dev/urandom is required to generate encryption key."

        fi

    fi
}

# ============================================================
# Read input
# ============================================================

ask_configuration() {

    echo
    echo "=============================================="
    echo "            AdBot Configuration"
    echo "=============================================="
    echo

    read -r -p "PostgreSQL database name [mybot_db]: " POSTGRES_DB
    POSTGRES_DB="${POSTGRES_DB:-mybot_db}"

    read -r -p "PostgreSQL username [mybot_user]: " POSTGRES_USER
    POSTGRES_USER="${POSTGRES_USER:-mybot_user}"

    read -r -s -p "PostgreSQL password: " POSTGRES_PASSWORD
    echo

    if [[ -z "${POSTGRES_PASSWORD}" ]]; then
        die "PostgreSQL password cannot be empty."
    fi

    read -r -p "Telegram bot token: " TELEGRAM_BOT_TOKEN

    if [[ -z "${TELEGRAM_BOT_TOKEN}" ]]; then
        die "Telegram bot token cannot be empty."
    fi

    read -r -p "Admin Telegram ID(s): " ADMIN_ID

    if [[ -z "${ADMIN_ID}" ]]; then
        die "Admin ID cannot be empty."
    fi

    echo
    echo "Encryption Key"
    echo "--------------"
    echo "1) Auto generate"
    echo "2) Manual"
    echo

    read -r -p "Select option [1]: " ENCRYPTION_OPTION
    ENCRYPTION_OPTION="${ENCRYPTION_OPTION:-1}"

    case "${ENCRYPTION_OPTION}" in

        1)

            ENCRYPTION_KEY="$(generate_encryption_key)"

            echo
            success "Encryption key generated"

            ;;

        2)

            read -r -p "Enter encryption key: " ENCRYPTION_KEY

            if [[ -z "${ENCRYPTION_KEY}" ]]; then
                die "Encryption key cannot be empty."
            fi

            ;;

        *)

            die "Invalid encryption option."

            ;;

    esac
}

# ============================================================
# Create .env
# ============================================================

create_env() {

    info "Creating .env"

    cat > "${ENV_FILE}" <<EOF
# AdBot Configuration

DEBUG=False

MAX_CONCURRENT_WORKERS=2000
SCHEDULER_INTERVAL=60

# PostgreSQL
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Telegram
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
ADMIN_ID=${ADMIN_ID}

# Auto Delete
AUTO_DELETE=false
AUTO_DELETE_TIME=120

# Encryption
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

    chmod 600 "${ENV_FILE}" 2>/dev/null || true

    success ".env created"
}

# ============================================================
# Check Docker files
# ============================================================

check_docker_files() {

    echo

    if [[ ! -f "${SCRIPT_DIR}/Dockerfile" ]]; then

        warn "Dockerfile not found."

        echo "Create Dockerfile before starting Docker."

    else

        success "Dockerfile found"

    fi

    if [[ ! -f "${SCRIPT_DIR}/docker-compose.yml" &&
          ! -f "${SCRIPT_DIR}/docker-compose.yaml" ]]; then

        warn "docker-compose.yml not found."

    else

        success "Docker Compose file found"

    fi
}

# ============================================================
# Docker Compose
# ============================================================

run_docker_compose() {

    if [[ "${DOCKER_AVAILABLE}" != "true" ]]; then

        warn "Docker is not available."

        echo
        echo "Install Docker and run:"
        echo
        echo "  docker compose up -d --build"
        echo

        return

    fi

    if ! docker info >/dev/null 2>&1; then

        warn "Docker daemon is not running."

        echo
        echo "Start Docker and run:"
        echo
        echo "  docker compose up -d --build"
        echo

        return

    fi

    if [[ ! -f "${SCRIPT_DIR}/docker-compose.yml" &&
          ! -f "${SCRIPT_DIR}/docker-compose.yaml" ]]; then

        warn "docker-compose.yml not found."
        return

    fi

    echo
    echo "=============================================="
    echo "          Starting Docker Compose"
    echo "=============================================="
    echo

    (
        cd "${SCRIPT_DIR}"

        docker compose up -d --build
    )

    success "Docker Compose started"
}

# ============================================================
# Summary
# ============================================================

show_summary() {

    echo
    echo "=============================================="
    echo "             Installation Complete"
    echo "=============================================="
    echo

    echo "Version       : ${VERSION}"
    echo "Target OS     : ${TARGET_OS}"
    echo "Target Arch   : ${TARGET_ARCH}"
    echo "Release Asset : ${RELEASE_ASSET}"
    echo "Binary        : ${DIST_DIR}/${BINARY_NAME}"
    echo "Environment   : ${ENV_FILE}"
    echo

    echo "Next:"
    echo "  docker compose up -d --build"
    echo
}

# ============================================================
# Main
# ============================================================

main() {

    banner

    check_tools

    detect_host_os

    detect_host_arch

    detect_docker

    detect_docker_platform

    select_target

    create_directories

    download_release

    verify_checksum

    install_binary

    ask_configuration

    create_env

    check_docker_files

    show_summary

    if [[ "${DOCKER_AVAILABLE}" == "true" ]]; then

        echo
        read -r -p "Start AdBot with Docker Compose now? [Y/n]: " START_DOCKER

        START_DOCKER="${START_DOCKER:-Y}"

        if [[ "${START_DOCKER}" =~ ^[Yy]$ ]]; then
            run_docker_compose
        fi

    else

        warn "Docker was not detected."

    fi

    echo
    success "AdBot installation finished."
    echo
}

main "$@"