#!/usr/bin/env bash

set -o errexit # Abort on nonzero exit code.
set -o nounset # Abort on unbound variable.
set -o pipefail # Don't hide errors within pipes.
# set -o xtrace   # Enable for debugging.

declare -r DISK_UUID="0d8df2a0-1ff4-4bb8-b155-f8d91efd9ebf"

if grep "${DISK_UUID}" /etc/fstab; then
    info "External drive already mounted."
else
    warning "External drive not mounted. Mounting now..."
    mkdir -p /mnt
    printf 'UUID=%s  /mnt		ext4	defaults	0	0' \
        "${DISK_UUID}" >> /etc/fstab
    mount -a || \
        error "Failed to mount external drive."
fi


# Install essential packages.
apt install -y \
    apache2 \
    mod_ssl

systemctl enable --now apache2

firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --add-port=8096/tcp --permanent
firewall-cmd --add-port=9300/tcp --permanent

firewall-cmd --add-port=51413/udp --permanent

firewall-cmd --reload

# Hide sensitive server information.
if [[ ! -d "/etc/apache2/conf.d" ]]; then
    mkdir -p /etc/apache2/conf.d
fi

########################
# Apache Reverse Proxy #
########################

# Generate a self-signed certificate.
key_location="/etc/apache2/conf/ssl.key/${SERVER_DOMAIN}.key"
crt_location="/etc/apache2/conf/ssl.key/${SERVER_DOMAIN}.crt"

[[ -f "${key_location}" ]] && rm -f "${key_location}"
[[ -f "${crt_location}" ]] && rm -f "${crt_location}"

mkdir -p /etc/apache2/conf/ssl.key
openssl req -newkey rsa:2048 -nodes -keyout "${key_location}" \
    -x509 -days 3650 -out "${crt_location}" \
    -subj "/C=BE/ST=Brussels/L=Brussels/O=Homer/OU=IT Department/CN=${SERVER_DOMAIN}"

ssl_config_location="/etc/apache2/conf.d/ssl.conf"
# Set the certificate file locations to the correct locations.
[[ -f "${ssl_config_location}" ]] && \
    sed -i "s,SSLCertificateFile /etc/pki/tls/certs/localhost.crt,SSLCertificateFile ${crt_location},g" "${ssl_config_location}"
[[ -f "${ssl_config_location}" ]] && \
    sed -i "s,SSLCertificateKeyFile /etc/pki/tls/private/localhost.key,SSLCertificateKeyFile ${key_location},g" "${ssl_config_location}"

# Set SeLinux to allow apache2 to write to the files directory.
setsebool -P apache2_anon_write 1

# Enable the required Apache modules.
a2emod proxy
a2enmod proxy_http
a2enmod ssl

# Disable the default Apache site.
a2dissite 000-default.conf

cat << EOF > /etc/apache2/sites-available/reverse-proxy-http.conf
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

cat << EOF > /etc/apache2/sites-available/reverse-proxy-https.conf
# Virtual Host for Pi-hole.
<VirtualHost *:443>
    ServerName pihole.${SERVER_DOMAIN}

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    SSLEngine on
    SSLHonorCipherOrder off
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://${MARGE_IP_ADDRESS}:80/
    ProxyPassReverse / http://${MARGE_IP_ADDRESS}:80/

    RewriteEngine On
    RewriteRule ^/$ /admin [R]
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

# Virtual Host for default website.
<VirtualHost *:443>
    ServerName ${SERVER_DOMAIN}
    ServerAdmin webmaster@${SERVER_DOMAIN}
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile ${crt_location}
    SSLCertificateKeyFile ${key_location}

    SSLEngine on
    SSLHonorCipherOrder off
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:8080/
    ProxyPassReverse / http://127.0.0.1:8080/
EOF

# Enable the reverse proxy sites.
a2ensite reverse-proxy-http.conf
a2ensite reverse-proxy-https.conf

# Set SeLinux to allow apache2 to connect to the network.
# This fixes the 503: Service Unavailable error.
setsebool -P apache2_can_network_connect 1

# Restart the apache2 service.
systemctl restart apache2

###########
# Grafana #
###########

apt install -y apt-transport-https
apt install -y software-properties-common wget
wget -i -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key

echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | \
    tee -a /etc/apt/sources.list.d/grafana.list

apt update
apt install -y grafana

systemctl daemon-reload
systemctl enable --now grafana-server

# Generate a API key for the admin user.
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

    for dashboard in ./files/grafana/dashboards/"${MACHINE_NAME,,}"/*.json; do
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

###################
# Podman & Docker #
###################

apt install -y podman

mkdir -p /var/lib/podman/volumes/configs/emby/config \
    /mnt/series \
    /mnt/movies \
    /mnt/documentaries

podman run -d \
    --name emby \
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

mkdir -p /var/lib/podman/volumes/configs/transmission/config \
    /mnt/transmission/downloads \
    /mnt/transmission/torrents

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
