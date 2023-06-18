#!/usr/bin/env bash

set -o errexit  # Abort on nonzero exit code.
set -o nounset  # Abort on unbound variable.
set -o pipefail # Don't hide errors within pipes.
# set -o xtrace   # Enable for debugging.

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

[[ -f ".env" ]] || \
    error "No '.env' file found. Please create one."

# Load the environment variables.
. ./.env

if id 1000 &> /dev/null; then
    info "User with UID 1000 already exists."
else
    info "Creating user ${USER_NAME}"
    useradd -u 1000 -m -s /bin/bash "${USER_NAME}"
    info "Setting password for user ${USER_NAME}"
    chpasswd <<< "${USER_NAME}:${USER_PASSWORD}"
fi

# Disable root login.
usermod -s /usr/sbin/nologin root

# Update the system.
apt update -y
apt dist-upgrade -y

# Install essential packages.
apt install -y \
    git \
    curl \
    wget \
    vim \
    tree \
    htop \
    tmux \
    jq \
    patch

################
# SSH Settings #
################

if [[ -f "/etc/ssh/sshd_config" ]]; then
    info "Backing up /etc/ssh/sshd_config to /etc/ssh/sshd_config.bak"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    info "Applying patch to /etc/ssh/sshd_config"
    patch -f /etc/ssh/sshd_config < ./files/patches/sshd_config.patch

    cp -r ./files/motd /etc/profile.d/motd.sh
    cp -r ./files/banner /etc/banner

    # In case we are installing the server on a remote machine, we don't want to
    # restart the sshd service. This way we don't lose the connection.
    if systemctl is-active --quiet sshd; then
        warning "There is an active SSH connection. Not restarting sshd."
    else
        log "Restarting sshd service"
        systemctl restart sshd
    fi
fi

####################
# Network Settings #
####################

info "Configuring the static hostname (${HOST_NAME})"
hostnamectl set-hostname "${HOST_NAME}"

case "${HOST_NAME}" in
    homer)
        declare -r IP_ADDRESS="${HOMER_IP_ADDRESS}"
        ;;
    marge)
        declare -r IP_ADDRESS="${MARGE_IP_ADDRESS}"
        ;;
    *)
        error "Unknown host: ${HOST_NAME}"
        ;;
esac

info "Configuring the static IP address"
info "The following settings will be applied:"
info "  IP Address: ${IP_ADDRESS}/${SUBNET_MASK_CIDR}"
info "  Gateway: ${DEFAULT_GATEWAY}"
info "  DNS Server: ${DNS_SERVER}"

cat << EOF > /etc/dhcpcd.conf
interface eth0
static ip_address=${P_ADDRESS}/${SUBNET_MASK_CIDR}
static routers=${DEFAULT_GATEWAY}
static domain_name_servers=${DNS_SERVER}
EOF

# Restart the network service.
systemctl restart dhcpcd

info "Configuring the timezone"
timedatectl set-timezone "${TIMEZONE}"

###########
# SELinux #
###########

info "Uninstalling AppArmor"
systemctl disable --now apparmor || \
    warning "AppArmor already stopped. Moving on."
apt purge -y apparmor

command -v selinux-activate &> /dev/null || {
    info "Installing SELinux"
    apt install -y \
        selinux-basics \
        selinux-policy-default \
        auditd

    selinux-activate

    # Ensure that SELinux is active.
    if [[ "$(getenforce)" != 'Enforcing' ]]; then
        setenforce 1

        # Change the SELinux mode to enforcing.
        sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    fi

    setsebool -P httpd_can_network_connect 1
} || warning "SELinux is already installed and configured. Moving on."

############
# Fail2Ban #
############

apt install -y fail2ban

systemctl enable --now fail2ban

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
patch /etc/fail2ban/jail.local < ./files/patches/jail.local.patch

########################
# Firewall (firewalld) #
########################

apt install -y firewalld

systemctl enable --now firewalld

firewall-cmd --permanent --zone=public --add-service=ssh
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=public --add-service=samba
firewall-cmd --permanent --zone=public --add-service=dns

firewall-cmd --permanent --zone=public --add-port=9100/tcp
firewall-cmd --permanent --zone=public --add-port=9200/tcp

firewall-cmd --reload

##############################
# Prometheus & Node Exporter #
##############################

if ! id prometheus >/dev/null 2>&1; then
    info "Creating Prometheus user and group"
    groupadd --system prometheus
    useradd -s /sbin/noinfoin --system -g prometheus prometheus

    info "Installing Prometheus"
    mkdir -p /var/lib/prometheus
    mkdir -p /etc/prometheus/{rules,rules.d,files_sd}

    curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | \
        grep browser_download_url | \
        grep linux-arm64 | \
        cut -d '"' -f 4 | \
        wget -i -

    tar -xzf prometheus-*.linux-arm64.tar.gz
    cp -r prometheus-*/{prometheus,promtool} /usr/local/bin/
    cp -r prometheus-*/{consoles,console_libraries,prometheus.yml} /etc/prometheus/

    chown -R prometheus:prometheus /etc/prometheus
    chown -R prometheus:prometheus /var/lib/prometheus
    chmod -R 775 /var/lib/prometheus

    cp "files/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml

    cp "files/systemd/prometheus.service" /etc/systemd/system/prometheus.service

    systemctl daemon-reload
    systemctl enable --now prometheus

    info "Installing Node Exporter"
    mkdir -p /var/lib/prometheus/node_exporter

    curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | \
        grep browser_download_url | \
        grep linux-arm64 | \
        cut -d '"' -f 4 | \
        wget -i -

    tar -xzf node_exporter-*.linux-arm64.tar.gz
    cp -r node_exporter-*/* /var/lib/prometheus/node_exporter/

    chown -R prometheus:prometheus /var/lib/prometheus/node_exporter
    chmod -R 775 /var/lib/prometheus/node_exporter

    cp -r /var/lib/prometheus/node_exporter/node_exporter /usr/local/bin/node_exporter

    cp "files/systemd/node_exporter.service" /etc/systemd/system/node_exporter.service

    systemctl daemon-reload
    systemctl enable --now node_exporter

    rm -rf prometheus-*.linux-arm64.tar.gz \
        node_exporter-*.linux-arm64.tar.gz \
        prometheus-* \
        node_exporter-*
fi

##########################
# Host specific settings #
##########################

if [[ -f "${HOST_NAME}.sh" ]]; then
    info "Running host specific settings for ${HOST_NAME}"
    . "./${HOST_NAME}.sh"
fi

success "All done!"