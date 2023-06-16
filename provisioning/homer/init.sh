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

# Optimize the DNF configuration.
cp -r ./files/dnf/dnf.conf /etc/dnf/dnf.conf

# Update the system.
dnf update -y

# Install essential packages.
dnf install -y \
    git \
    vim-enhanced \
    tree \
    jq \
    httpd \
    mod_ssl

# Enable essential services.
systemctl enable --now firewalld

####################
# Network Settings #
####################

# Configure the static hostname.
hostnamectl set-hostname "${HOST_NAME}"

# Configure the static IP address.
nmcli connection modify "${NETWORK_INTERFACE}" ipv4.addresses "${HOMER_IP_ADDRESS}/${SUBNET_MASK_CIDR}"
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
cp -r ./files/motd /etc/profile.d/motd.sh

############
# Firewall #
############

firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-service=ssh --permanent
firewall-cmd --add-service=samba --permanent

firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --add-port=8096/tcp --permanent
firewall-cmd --add-port=9100/tcp --permanent
firewall-cmd --add-port=9200/tcp --permanent
firewall-cmd --add-port=9300/tcp --permanent

firewall-cmd --add-port=51413/udp --permanent
firewall-cmd --add-port=51820/udp --permanent

firewall-cmd --reload

# Hide sensitive server information.
if [[ ! -d "/etc/httpd/conf.d" ]]; then
    mkdir -p /etc/httpd/conf.d
fi

cat << EOF > /etc/httpd/conf.d/security.conf
ServerTokens Prod
ServerSignature Off
EOF

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

########################
# Apache Reverse Proxy #
########################

# Generate a self-signed certificate.
key_location="/etc/httpd/conf/ssl.key/${SERVER_DOMAIN}.key"
crt_location="/etc/httpd/conf/ssl.key/${SERVER_DOMAIN}.crt"

[[ -f "${key_location}" ]] && rm -f "${key_location}"
[[ -f "${crt_location}" ]] && rm -f "${crt_location}"

mkdir -p /etc/httpd/conf/ssl.key
openssl req -newkey rsa:2048 -nodes -keyout "${key_location}" \
    -x509 -days 3650 -out "${crt_location}" \
    -subj "/C=BE/ST=Brussels/L=Brussels/O=Homer/OU=IT Department/CN=${SERVER_DOMAIN}"

ssl_config_location="/etc/httpd/conf.d/ssl.conf"
# Set the certificate file locations to the correct locations.
[[ -f "${ssl_config_location}" ]] && \
    sed -i "s,SSLCertificateFile /etc/pki/tls/certs/localhost.crt,SSLCertificateFile ${crt_location},g" "${ssl_config_location}"
[[ -f "${ssl_config_location}" ]] && \
    sed -i "s,SSLCertificateKeyFile /etc/pki/tls/private/localhost.key,SSLCertificateKeyFile ${key_location},g" "${ssl_config_location}"

# Set SeLinux to allow httpd to write to the files directory.
setsebool -P httpd_anon_write 1

# Write modules to load to the httpd.conf file.
cat << EOF >> /etc/httpd/conf/httpd.conf
LoadModule ssl_module /usr/lib64/apache2-prefork/mod_ssl.so
LoadModule proxy_module modules/proxy.so
LoadModule proxy_http_module modules/proxy_http
EOF

cat << EOF > /etc/httpd/conf.d/reverse-proxy-http.conf
# Redirect all http traffic to https.
<VirtualHost *:80>
    ServerName ${SERVER_DOMAIN}
    ServerAdmin webmaster@${SERVER_DOMAIN}
    DocumentRoot /var/www/html

    # Redirect HTTP traffic to HTTPS equivalent
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</VirtualHost>
EOF

cat << EOF > /etc/httpd/conf.d/reverse-proxy-https.conf
# Virtual Host for Pi-hole.
<VirtualHost *:443>
    ServerName pihole.${SERVER_DOMAIN}

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass /admin/ http://${MARGE_IP_ADDRESS}:80/admin/
    ProxyPassReverse /admin/ http://${MARGE_IP_ADDRESS}:80/admin/
</VirtualHost>

# Virtual Host for Grafana.
<VirtualHost *:443>
    ServerName grafana.${SERVER_DOMAIN}

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
</VirtualHost>

# Virtual Host for Emby.
<VirtualHost *:443>
    ServerName emby.${SERVER_DOMAIN}

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:8096/
    ProxyPassReverse / http://127.0.0.1:8096/
</VirtualHost>

# Virtual Host for Transmission.
<VirtualHost *:443>
    ServerName transmission.${SERVER_DOMAIN}

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:9300/
    ProxyPassReverse / http://127.0.0.1:9300/
</VirtualHost>

# Virtual Host for Samba Share on Marge.
<VirtualHost *:445>
    ServerName nas.${SERVER_DOMAIN}

    ProxyPreserveHost On
    ProxyRequests Off

    # ProxyPass and ProxyPassReverse to your NAS IP and Samba port
    ProxyPass / smb://${MARGE_IP_ADDRESS}:445/
    ProxyPassReverse / smb://${MARGE_IP_ADDRESS}:445/

    # If authentication is required, you can add the following line
    ProxyPassReverseCookieDomain ${MARGE_IP_ADDRESS} nas.${SERVER_DOMAIN}
</VirtualHost>
EOF

# Set SeLinux to allow httpd to connect to the network.
# This fixes the 503: Service Unavailable error.
setsebool -P httpd_can_network_connect 1

# Restart the httpd service.
systemctl restart httpd

###########
# Grafana #
###########

cp "files/yum/repos/grafana.repo" /etc/yum.repos.d/grafana.repo
dnf install -y grafana

systemctl daemon-reload
systemctl enable --now grafana-server

# Generate a API key for the admin user.
command -v jq >/dev/null 2>&1 || dnf install -y jq
grafana_api_key=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"vagrant","role":"Admin"}' \
    http://admin:admin@localhost:3000/api/auth/keys | jq -r '.key')

declare -a MACHINES
MACHINES=(
    "Homer ${HOMER_IP_ADDRESS}"
    "Marge ${MARGE_IP_ADDRESS}"
)

for MACHINE in "${MACHINES[@]}"; do
    MACHINE_NAME="${MACHINE%% *}"
    MACHINE_IP="${MACHINE##* }"

    # Create Prometheus data sources for each machine.
    curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${grafana_api_key}" \
        -d "{
            \"name\":\"Prometheus-${MACHINE_NAME}\",
            \"type\":\"prometheus\",
            \"url\":\"http://${MACHINE_IP}:9200\",
            \"access\":\"proxy\",
            \"basicAuth\":false
        }" \
        http://localhost:3000/api/datasources

    # Create folders for each machine.
    curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${grafana_api_key}" \
        -d "{\"title\": \"${MACHINE_NAME}\"}" \
        http://localhost:3000/api/folders

    # Import dashboards for each machine.
    folder_id=$(curl -s -H "Authorization: Bearer ${grafana_api_key}" \
        http://localhost:3000/api/search | \
        jq -r ".[] | select(.type == \"dash-folder\") | select(.title == \"${MACHINE_NAME}\") | .id")

    for dashboard in ./files/grafana/"${MACHINE_NAME,,}"/*.json; do
        curl -s -X POST -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${grafana_api_key}" \
            -d "{
                \"dashboard\":$(cat "${dashboard}"),
                \"folderId\":${folder_id},
                \"overwrite\":true
            }" \
            http://localhost:3000/api/dashboards/import
    done
done

curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${grafana_api_key}" \
    -d "{
        \"name\":\"Discord\",
        \"type\":\"discord\",
        \"settings\":{
            \"url\":\"${DISCORD_WEBHOOK_URL}\",
            \"sendReminder\":true
        }
    }" \
    http://localhost:3000/api/v1/provisioning/contact-points

# Delete the API key for the admin user, as it is no longer needed.
curl -S -X DELETE -H "Content-Type: application/json" \
    -d '{"name":"vagrant","role":"Admin"}' \
    http://admin:admin@localhost:3000/api/auth/keys/1

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

    mkdir -p /var/lib/prometheus/node_exporter

    curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | \
        grep browser_download_url | \
        grep linux-arm64 | \
        cut -d '"' -f 4 | \
        wget -qi -

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

###################
# Podman & Docker #
###################

dnf module install -y container-tools:ol8

mkdir -p /var/lib/podman/volumes/configs/emby/config

podman run -d \
    --env PUID=10000 \
    --env PGID=1000 \
    --env TZ="${TIMEZONE}" \
    --volume /var/lib/podman/volumes/configs/emby:/config:Z \
    --volume /mnt/series:/data/series:Z \
    --volume /mnt/movies:/data/movies:Z \
    --volume /mnt/documentaries:/data/documentaries:Z \
    --publish 8096:8096 \
    docker.io/emby/embyserver:latest

podman generate systemd --new --name emby > /etc/systemd/system/emby.service
systemctl daemon-reload
systemctl enable --now emby.service

podman run -d \
    --name transmission \
    --env PUID=10000 \
    --env PGID=1000 \
    --env TZ="${TIMEZONE}" \
    --volume /var/lib/podman/volumes/configs/transmission/config:/config:Z \
    --volume /mnt/transmission/downloads:/downloads:Z \
    --volume /mnt/transmission/torrents:/watch:Z \
    --publish 9300:9091/tcp \
    --publish 51413:51413/tcp \
    --publish 51413:51413/udp \
    lscr.io/linuxserver/transmission:latest

podman generate systemd --new --name transmission > /etc/systemd/system/transmission.service
systemctl daemon-reload
systemctl enable --now transmission.service
