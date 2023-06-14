<div align="center">
    <h1>
        Homelab Automation - Still a work in progress!
    </h1>
    <p align="center">
        All scripts used to automate the setup of my homelab 
        <br/>
        <strong>·</strong>
        <a href="https://github.com/AntonVanAssche/homelab-automation/issues">Report Bug</a>
        <strong>·</strong>
        <a href="https://github.com/AntonVanAssche/homelab-automation/issues">Request Feature</a>
   </p>
</div>

## About The Project

The Homelab Project is a personal endeavor to create a small-scale, self-hosted infrastructure using two Raspberry Pi 4B devices. The project consists of two servers, named Homer and Marge, each serving different purposes within the homelab environment.

## Server: Homer

Homer serves primarily as a hometheater media server, hosting an Emby instance to provide media streaming capabilities. Emby is a media server application that allows for the streaming of media files to a wide range of devices.

Besides Emby, Homer also hosts a transmission-daemon instance to enable torrenting capabilities. Transmission is a BitTorrent client that allows for the downloading and seeding of torrent files. It is configured to use a VPN connection to ensure that all torrent traffic is encrypted and secure.

Probably the most important feature of Homer is the Grafana instance that is hosted on it. Allowing me to monitor both Homer and Marge from a web interface. Both servers are monitored using Prometheus and Node Exporter. Dashboards are created using Grafana's API and are automatically provisioned using the provisioning script.

## Server: Marge

<img src="https://cdn.shopify.com/s/files/1/0021/1497/7894/products/2020428_6_1024x1024.jpg?v=1600062159" alt="img" align="right" width="25%">

Marge is a dedicated Network-Attached Storage (NAS) server configured with a RAID 5 array using four SATA HDDs. It offers reliable data storage and access within the homelab environment. Samba, an open-source implementation of the Server Message Block (SMB) protocol, is installed on Marge to enable seamless file sharing and network integration.

In a typical Raspberry Pi setup, connecting SATA devices directly is not possible. However, with the help of the Raxda Rock Pi SATA HAT, Marge overcomes this limitation. The SATA HAT allows for the connection of up to four SATA devices to a single Raspberry Pi. It achieves this by utilizing the GPIO pins and USB 3 buses on the Raspberry Pi, enabling the SATA devices to be connected to the SATA HAT via its SATA ports.

To facilitate the usage of the Raxda Rock Pi SATA HAT, a script has been created that builds an RPM file. This RPM file can be installed on any RHEL-based system. The script can be found in the `rockpi-sata` directory, while a pre-built RPM file is available in the `rockpi-sata/pkgs` directory. This script is required since Raxda does not provide an RPM file for the SATA HAT, but only a Debian package instead.

By leveraging the power of Samba, Marge enables seamless access and interaction with the stored data from other devices on the network. Computers running Windows, macOS, or Linux can effortlessly connect to Marge and take advantage of the SMB protocol's compatibility and interoperability features. This allows for efficient file transfers, sharing, and collaborative workflows, regardless of the operating system being used.

Besides Samba, Marge also hosts a Pihole instance to provide network-wide ad-blocking capabilities. Pihole is a DNS sinkhole that blocks advertisements and trackers at the network level. It is configured to use the Unbound DNS resolver to provide DNS-over-TLS (DoT) and DNS-over-HTTPS (DoH) capabilities. This ensures that all DNS queries are encrypted and secure, preventing any malicious actors from intercepting and manipulating the DNS traffic. Marge also provides a WireGuard VPN server to enable secure remote access to the homelab environment from anywhere in the world.

## Setup Guide

In order to configure one of the servers you'll have to create the following `.env` file in the root directory of each server (i.e. `provisioning/homer` or `provisioning/marge`)):

```
# Network configuration
NETWORK_INTERFACE=              # e.g. "Wired connection 1"
HOMER_IP_ADDRESS=               # e.g. "192.168.0.66"
MARGE_IP_ADDRESS=               # e.g. "192.168.0.67"
SUBNET_MASK_CIDR=               # e.g. "24"
DEFAULT_GATEWAY=                # e.g. "192.168.0.1"
DNS_SERVER=                     # e.g. "1.1.1.1"

# Host configuration
HOST_NAME=                      # "homer" or "marge"
USER_NAME=                      # "homer" or "marge"
USER_PASSWORD=                  # e.g. "password", but a bit more secure ;)

# Server configuration
SERVER_DOMAIN=                  # e.g. "homelab.local"

# Timezone configuration
TIMEZONE=                       # e.g. "Europe/Brussels"
```

Afterwards, you start the configuration process by running the following command:

```console
# bash init.sh
```

**Note:** The script **must** be run as root (`sudo -i`).

## Contributing

Feel free to contribute to this repository by submitting pull requests with improvements, bug fixes, or additional server configurations. Your contributions are highly appreciated!

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
