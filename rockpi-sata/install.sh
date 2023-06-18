#!/usr/bin/env bash

set -o errexit  # Abort on nonzero exit code.
set -o noglob   # Disable globbing.
set +o xtrace   # Disable debug mode.
set -o pipefail # Don't hide errors within pipes.

# Colors
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly BLUE=$'\033[0;34m'

# Reset color
readonly NC=$'\033[0m'

error() {
    printf '%s' "${RED}Error: ${1}${NC}" >&2
    printf '\n'
    exit 1
}

info() {
    printf '%s' "${BLUE}Info: ${1}${NC}"
    printf '\n'
}

success() {
    printf '%s' "${GREEN}Success: ${1}${NC}"
    printf '\n'
}

warning() {
    printf '%s' "${YELLOW}Warning: ${1}${NC}"
    printf '\n'
}

[[ "${UID}" -eq 0 ]] || \
    error "Root privileges are required to run this."

[[ -f "/etc/os-release" ]] || \
    error "This script only supports Linux distributions using systemd."

. /etc/os-release

case "${ID}" in
    debian|ubuntu)
        info "${ID} detected, which is supported."
        ;;
    *)
        error "${ID} detected, which is not supported."
        ;;
esac

pip_fixpath() {
    path="/usr/local/lib/python$(python3 -V | cut -c8-10)/dist-packages"
    if [ ! -d "${path}" ]; then
        mkdir -p "${path}"
    fi
}

pip_clean() {
    local -a PACKAGES=(
        Adafruit-GPIO
        Adafruit-PureIO
        Adafruit-SSD1306
    )

    for package in "${PACKAGES[@]}"; do
        if pip3 list 2> /dev/null | grep "${package}" > /dev/null; then
            sudo -H pip3 uninstall "${package}" -y
        fi
    done
}

pip_install() {
    pip_fixpath
    pip_clean

    TEMP_ZIP="$(mktemp)"
    TEMP_DIR="$(mktemp -d)"
    curl -sL "${SSD1306}" -o "${TEMP_ZIP}"
    unzip "${TEMP_ZIP}" -d "${TEMP_DIR}" > /dev/null
    cd "${TEMP_DIR}/Adafruit_SSD1306-v1.6.2"
    python3 setup.py install && cd -
    rm -rf "${TEMP_ZIP}" "${TEMP_DIR}"
}

dtb_enable() {
    python3 /usr/bin/rockpi-sata/misc.py open_w1_i2c
}

check_pkgs() {
    local -a PACKAGES=(
        python3-rpi.gpio
        python3-setuptools
        python3-pip
        python3-pil
        python3-spidev
        pigpio
        python3-pigpio
    )
    local NEED_INSTALL=()

    for package in "${PACKAGES[@]}"; do
        if apt list --installed 2> /dev/null | grep "${package}" > /dev/null; then
            info "${package} is installed."
        else
            NEED_INSTALL+=("$package")
        fi
    done

    if [ ${#NEED_INSTALL[@]} -gt 0 ]; then
        info "Installing missing packages..."
        apt update
        apt install -y "${NEED_INSTALL[@]}"
    fi
}

install_scripts() {
    local SCRIPTS_DIR="/usr/bin/rockpi-sata"

    if [ -d "${SCRIPTS_DIR}" ]; then
        info "Scripts directory already exists."
        return
    fi

    info "Installing scripts..."
    install -m 0644 usr/bin/rockpi-sata/{fan,main,misc,oled}.py "${SCRIPTS_DIR}/"
    install -m 0644 usr/bin/rockpi-sata/fonts/*.ttf "${SCRIPTS_DIR}/fonts/"
}

install_config() {
    local CONFIG_FILE="/etc/rockpi-sata.conf"

    if [ -f "${CONFIG_FILE}" ]; then
        info "Config file already exists."
        return
    fi

    info "Installing config file..."
    install -m 644 /usr/bin/rockpi-sata/rockpi-sata.conf "${CONFIG_FILE}"
}

install_service() {
    local SERVICE_FILE="/lib/systemd/system/rockpi-sata.service"

    if [ -f "${SERVICE_FILE}" ]; then
        info "Service file already exists."
        return
    fi

    info "Installing service file..."
    cp -r /usr/bin/rockpi-sata/rockpi-sata.service "${SERVICE_FILE}"
}

enable_services() {
    systemctl daemon-reload

    systemctl enable --now rockpi-sata.service
    systemctl enable --now pigpiod.service
}


main() {
    check_pkgs
    pip_install
    install_scripts
    install_config
    install_service
    dtb_enable
    enable_services
    success "Installation completed."
}

main "${@}"