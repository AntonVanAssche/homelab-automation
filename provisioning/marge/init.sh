#!/usr/bin/env bash

set -o errexit # Abort on nonzero exit code.
set -o nounset # Abort on unbound variable.
set -o pipefail # Don't hide errors within pipes.
# set -o xtrace   # Enable for debugging.

# Source the ENV variables.
. ./.env

# Ensure that SELinux is active.
if [[ "$(getenforce)" != 'Enforcing' ]]; then
    setenforce 1

    # Change the SELinux mode to enforcing.
    sed -i 's/SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

# Disable the root account.
usermod -s /usr/sbin/nologin root

# Update the system.
dnf update -y

# Install essential packages.
dnf install -y \
    git \
    vim-enhanced \
    tree \
    jq \
    patch \
    epel-release \
    mdadm

# Enable essential services.
systemctl enable --now firewalld

####################
# Network Settings #
####################

# Configure the static hostname.
hostnamectl set-hostname "${HOST_NAME}"

# Configure the static IP address.
nmcli connection modify "${NETWORK_INTERFACE}" ipv4.addresses "${MARGE_IP_ADDRESS}/${SUBNET_MASK_CIDR}"
nmcli connection modify "${NETWORK_INTERFACE}" ipv4.gateway "${DEFAULT_GATEWAY}"
nmcli connection modify "${NETWORK_INTERFACE}" ipv4.dns "${DNS_SERVER}"
nmcli connection modify "${NETWORK_INTERFACE}" ipv4.method manual

# Restart the network service.
systemctl restart NetworkManager

# Configure the timezone.
timedatectl set-timezone "${TIMEZONE}"

#######
# SSH #
#######

patch /etc/ssh/sshd_config < ./files/patches/sshd_config.patch
cp -r ./files/motd /etc/motd

############
# Firewall #
############

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=dns --permanent
firewall-cmd --add-service=ssh --permanent
firewall-cmd --add-service=samba --permanent

firewall-cmd --add-port=9100/tcp --permanent
firewall-cmd --add-port=9200/tcp --permanent

firewall-cmd --add-port=51820/udp --permanent

firewall-cmd --reload

# Create the user account.
if ! id "${USER_NAME}" &>/dev/null; then
    useradd -m -s /bin/bash "${USER_NAME}"
    usermod -aG wheel "${USER_NAME}"
    printf '%s' "${USER_PASSWORD}" | passwd "${USER_NAME}" --stdin
fi

############
# Fail2Ban #
############

dnf install -y \
    fail2ban\
    fail2ban-firewalld

systemctl enable --now fail2ban

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
patch /etc/fail2ban/jail.local < ./files/patches/jail.local.patch

############################
# Promethues Node Exporter #
############################

if ! id prometheus >/dev/null 2>&1; then
    groupadd --system prometheus
    useradd -s /sbin/nologin --system -g prometheus prometheus

    mkdir -p /var/lib/prometheus
    mkdir -p /etc/prometheus/{rules,rules.d,files_sd}

    curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | \
        grep browser_download_url | \
        grep linux-arm64 | \
        cut -d '"' -f 4 | \
        wget -qi -

    tar -xzf prometheus-*.linux-amd64.tar.gz
    cp -r prometheus-*/{prometheus,promtool} /usr/local/bin/
    cp -r prometheus-*/{consoles,console_libraries,prometheus.yml} /etc/prometheus/

    chown -R prometheus:prometheus /etc/prometheus
    chown -R prometheus:prometheus /var/lib/prometheus
    chmod -R 775 /var/lib/prometheus

    cp "files/prometheus/prometheus.yml" /etc/prometheus/prometheus.yml

    cp "files/systemd/prometheus.service" /etc/systemd/system/prometheus.service

    systemctl daemon-reload
    systemctl enable --now prometheus

    mkdir -p /var/lib/prometheus/node_exporter

    curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | \
        grep browser_download_url | \
        grep linux-arm64 | \
        cut -d '"' -f 4 | \
        wget -qi -

    tar -xzf node_exporter-*.linux-amd64.tar.gz
    cp -r node_exporter-*/* /var/lib/prometheus/node_exporter/

    chown -R prometheus:prometheus /var/lib/prometheus/node_exporter
    chmod -R 775 /var/lib/prometheus/node_exporter

    cp -r /var/lib/prometheus/node_exporter/node_exporter /usr/local/bin/node_exporter

    cp "files/systemd/node_exporter.service" /etc/systemd/system/node_exporter.service

    systemctl daemon-reload
    systemctl enable --now node_exporter

    rm -rf prometheus-*.linux-amd64.tar.gz \
        node_exporter-*.linux-amd64.tar.gz \
        prometheus-* \
        node_exporter-*
fi

###################
# Podman & Docker #
###################

dnf module install -y container-tools:ol8

sudo podman network create \ 
    --driver macvlan \
    --opt parent=enp4s0 \
    --subnet 192.168.0.0/24 \
    --gateway 192.168.0.1 \
    --ip-range 192.168.0.230/24 podman-vlan

cp files/systemd/podman-network.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now podman-network.service

podman run -d \
    --name pihole \
    --cap-add=NET_ADMIN \
    --net=mymacnet \
    --ip=192.168.0.230 \
    -v "/home/${USER_NAME}/configs/pihole:/etc/pihole" \
    -v "/home/${USER_NAME}/configs/dnsmasq.d:/etc/dnsmasq.d" \
    --restart=unless-stopped \
    --hostname pihole \
    --security-opt label=disable \
    -e TZ="${TIMEZONE}" \
    -e FTLCONF_LOCAL_IPV4=192.168.0.230 \
    docker.io/pihole/pihole:latest

podman generate systemd --new --name pihole > /etc/systemd/system/pihole.service
systemctl daemon-reload
systemctl enable --now pihole.service

#################
# Raxda Drivers #
#################

dnf install -y \
    python3-rpi-gpio2 \
    python3-setuptools \
    python3-pip \
    python3-pillow \
    python3-spidev \
    pigpio

dnf install -y ../../rockpi-sata/pkgs/*.rpm

pip3 install Adafruit-GPIO \
    Adafruit-PureIO \
    Adafruit-SSD1306

# Eable DTB.
python3 /usr/bin/rockpi-sata/misc.py open_w1_i2c

##########
# RAID 5 #
##########

mdadm --assemble --scan --verbose
mdadm --detail --scan | tee /etc/mdadm.conf

mkdir -p /mnt/nas
chown -R "${USER_NAME}":"${USER_NAME}" /mnt/nas

cp -r files/systemd/mnt-nas.mount /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now mnt-nas.mount

###############
# Samba Share #
###############

dnf install -y samba

smbpasswd -a "${USER_NAME}"

patch /etc/samba/smb.conf < ./files/patches/smb.conf.patch

systemctl enable --now smb
