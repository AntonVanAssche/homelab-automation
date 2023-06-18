#!/usr/bin/env bash

set -o errexit # Abort on nonzero exit code.
set -o nounset # Abort on unbound variable.
set -o pipefail # Don't hide errors within pipes.
# set -o xtrace   # Enable for debugging.

############
# Firewall #
############

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=dns --permanent

firewall-cmd --add-port=51820/udp --permanent

firewall-cmd --permanent --zone=public --add-masquerade

firewall-cmd --reload

###################
# Podman & Docker #
###################

apt install -y podman

# Unbound DNS server.
mkdir -p /var/lib/podman/volumes/configs/unbound

podman images -a --format "{{.Names}}" | grep "unbound" &> /dev/null || \
    podman run -d \
        --name=unbound \
        --publish 5353:53/tcp \
        --publish 5353:53/udp \
        --volume /var/lib/podman/volumes/configs/unbound:/etc/unbound:Z \
        docker.io/klutchell/unbound:latest

# Pi-hole DNS sinkhole.
mkdir -p /var/lib/podman/volumes/configs/{pihole,dnsmasq.d}

# Fix port 53 already bound error.
# This port is used by systemd-resolved.
systemctl disable --now systemd-resolved
unlink /etc/resolv.conf
ifdown "${NETWORK_INTERFACE}" && ifup "${NETWORK_INTERFACE}"

# We have to wait for the network to be up.
sleep 5
podman images -a --format "{{.Names}}" | grep "pihole" &> /dev/null || \
    podman run -d \
        --name pihole \
        --env TZ="${TIMEZONE}" \
        --env WEBPASSWORD="${PIHOLE_PASSWORD}" \
        --env PIHOLE_DNS_="127.0.0.1#5353,8.8.8.8" \
        --env DNSSEC=true \
        --volume /var/lib/podman/volumes/configs/pihole:/etc/pihole:Z \
        --volume /var/lib/podman/volumes/configs/dnsmasq.d:/etc/dnsmasq.d:Z \
        --publish 53:53/tcp \
        --publish 53:53/udp \
        --publish 80:80/tcp \
        docker.io/pihole/pihole:latest

podman generate systemd --new --name pihole > /etc/systemd/system/pihole.service
systemctl daemon-reload
systemctl enable --now pihole.service

#################
# Wireguard VPN #
#################

modprobe wireguard

apt install -y \
    wireguard \
    qrencode

mkdir -p "/etc/wireguard/${HOSTNAME}"

info "Enabling IP forwarding."
[[ -f "/etc/sysctl.conf" ]] && \
    cat << EOF >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
EOF

sysctl -p

info "Generating Wireguard keys."
wg genkey | \
    tee "/etc/wireguard/${HOSTNAME}.private.key" | \
    wg pubkey > "/etc/wireguard/${HOSTNAME}.public.key"

chmod 600 "/etc/wireguard/${HOSTNAME}.private.key" \
    "/etc/wireguard/${HOSTNAME}.public.key"

info "Generating Wireguard configuration file."
cat << EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(cat "/etc/wireguard/${HOSTNAME}.private.key")
Address = 10.82.146.1/24
MTU = 1420
ListenPort = 51820
EOF

systemctl enable --now wg-quick@wg0

mkdir -p /etc/wireguard/clients

declare -a CLIENTS=(
    "laptop"
    "phone"
)

declare -i i=2

info "Generating Wireguard clients"
for client_name in "${CLIENTS[@]}"; do
    info "Generating Wireguard keys for client ${client_name}."
    wg genkey | \
        tee "/etc/wireguard/clients/wg0-client-${client_name}.private.key" | \
        wg pubkey > "/etc/wireguard/clients/wg0-client-${client_name}.public.key"
    wg genpsk > "/etc/wireguard/clients/wg0-client-${client_name}.psk"
    
    chmod 600 "/etc/wireguard/clients/wg0-client-${client_name}.private.key" \
        "/etc/wireguard/clients/wg0-client-${client_name}.public.key" \
        "/etc/wireguard/clients/wg0-client-${client_name}.psk"
    
    info "Generating Wireguard configuration file for client ${client_name}."
    cat << EOF > "/etc/wireguard/clients/wg0-client-${client_name}.conf"
[Interface]
PrivateKey = $(cat "/etc/wireguard/clients/wg0-client-${client_name}.private.key")
Address = 10.82.146.${i}/24
DNS = ${MARGE_IP_ADDRESS}

[Peer]
PublicKey = $(cat "/etc/wireguard/${HOSTNAME}.public.key")
PreSharedKey = $(cat "/etc/wireguard/clients/wg0-client-${client_name}.psk")
Endpoint = ${PUBLIC_IP_ADDRESS}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 30
EOF

    info "Adding client ${client_name} to Wireguard configuration file."
    cat << EOF >> /etc/wireguard/wg0.conf

# BEGIN ${client_name}
[Peer]
PublicKey = $(cat "/etc/wireguard/clients/wg0-client-${client_name}.public.key")
PreSharedKey = $(cat "/etc/wireguard/clients/wg0-client-${client_name}.psk")
AllowedIPs = 10.82.146.${i}/32
# END ${client_name}
EOF

    # Generate QR codes and save them to PNG files.
    info "Generating QR codes for client ${client_name}."
    qrencode -t ansiutf8 < "/etc/wireguard/clients/wg0-client-${client_name}.conf"
    qrencode -t png -o "/etc/wireguard/clients/wg0-client-${client_name}.png" < "/etc/wireguard/clients/wg0-client-${client_name}.conf"

    i=$((i++))
done

systemctl restart wg-quick@wg0

##########
# RAID 5 #
##########

info "Installing mdadm."
apt install -y mdadm

info "Scanning for RAID devices."
mdadm --assemble --scan --verbose
mdadm --detail --scan | tee /etc/mdadm.conf

info "Configuring mount point for RAID 5 array."
mkdir -p /mnt/nas
chown -R "${USER_NAME}":"${USER_NAME}" /mnt/nas

info "Mounting RAID 5 array."
cp -r files/systemd/mnt-nas.mount /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now mnt-nas.mount

###############
# Samba Share #
###############

apt install -y samba

{ printf '%s\n' "${USER_PASSWORD}"; printf '%s\n' "${USER_PASSWORD}"; } | \
    smbpasswd -a "${USER_NAME}"

info "Backing up the default Samba configuration file."
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

info "Patching the Samba configuration file."
patch /etc/samba/smb.conf < ./files/patches/smb.conf.patch

systemctl enable --now smbd