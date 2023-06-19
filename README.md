<div align="center">
    <h1>
        Homelab Automation
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

<img src="./assets/raspberry-pi-4b.png" alt="img" align="right" width="25%">

The Homelab Project is a personal endeavor to create a small-scale, self-hosted infrastructure using two Raspberry Pi 4B devices.
The project consists of two servers, named Homer and Marge, each serving different purposes within the homelab environment.
Both servers run Debian Bullseye and are completely automated using Bash scripts.
The script will install and configure things like AppArmor, firewalld, Podman and server specific applications.
And yes I know that firewalld isn't a normal choice for a debian based distribution, but I like it more than ufw, so deal with it 😁.
Same goes for Podman, I just like it more than Docker, so I'm using it instead.

## Encountered Issues

Originally, I was planning on using a RHEL-based distribution for the servers, such as Oracle Linux 9 or Fedora Server 38.
But due to the lack of support for the Raxda Rock Pi SATA HAT, I had to switch to Debian Bullseye.
I tried to get the SATA HAT working on Fedora Server 38 by packaging the drivers myself in a RPM package, which successfully installed the drivers.
But made me end up in the well beloved "Dependency Hell" and I couldn't get the drivers to work properly.
For example, the GPIO drivers are packaged differently in Fedora Server 38 than in Debian Bullseye, which meant that I had to rewrite the SATA HAT drivers to get them to work with the GPIO drivers in Fedora Server 38.

## Server: Homer

Emby takes the spotlight on Homer, functioning as the media streaming powerhouse. With Emby, I can effortlessly stream my media files to various devices throughout my home. It provides a seamless and enjoyable media experience, allowing me to access my favorite movies, TV shows, and documentaries with ease.

Torrenting capabilities are also integrated into Homer through its transmission-daemon instance. Transmission serves as a BitTorrent client, empowering me to download and seed torrent files efficiently. It adds another dimension of content acquisition to my media server setup.

Additionally, Homer boasts an essential component: Grafana. This powerful tool enables me to monitor both Homer and Marge through an intuitive web interface. Thanks to Prometheus and Node Exporter, both servers are continuously monitored, providing valuable insights into their performance and health.

To streamline the monitoring process, I've automated the creation of Grafana dashboards using Grafana's API. These dashboards are automatically provisioned using a dedicated provisioning script, ensuring that I have access to the most relevant and up-to-date information at all times.

In summary, Homer is a multifaceted server that elevates my media streaming experience with Emby, empowers torrenting with Transmission, and facilitates comprehensive monitoring through Grafana, Prometheus, and Node Exporter. It serves as a central hub for all my media-related activities and ensures that my servers are running optimally and efficiently.

## Server: Marge

<img src="./assets/rockpi-sata-kit.png" alt="img" align="right" width="25%">

Marge is my dedicated Network-Attached Storage (NAS) server designed to provide secure data storage and advanced network functionalities within my homelab environment. Marge is equipped with a RAID 5 array, comprising four SATA HDDs, ensuring data redundancy and availability.

To seamlessly integrate Marge into the network, I've deployed Samba, an open-source implementation of the Server Message Block (SMB) protocol. Samba enables effortless file sharing and network integration, allowing other devices on the network to access and interact with the stored data. Whether it's a Windows, macOS, or Linux machine, Marge provides compatibility and interoperability, facilitating smooth file transfers, sharing, and collaborative workflows across different operating systems.

To expand Marge's capabilities, I've integrated additional services that enhance network security and privacy. First, I've set up a Pihole instance, utilizing Unbound as the DNS forwarder. Pihole acts as a DNS sinkhole, effectively blocking advertisements and trackers at the network level. With Pihole in place, all devices within the network benefit from network-wide ad-blocking, providing a cleaner and more streamlined browsing experience.

In addition to ad-blocking, Marge serves as a WireGuard VPN server, ensuring secure remote access to the homelab environment. WireGuard, a modern and efficient VPN protocol, enables encrypted communication between external devices and the network. This allows me to connect to the homelab securely from anywhere in the world, accessing resources and services hosted on Marge with peace of mind.

To overcome the limitations of connecting SATA devices directly to a Raspberry Pi, I've integrated the Raxda Rock Pi SATA HAT into Marge's setup. This HAT expands the Raspberry Pi's capabilities, allowing the connection of up to four SATA devices. By utilizing the GPIO pins and USB 3 buses, the SATA devices seamlessly integrate with Marge's storage infrastructure, providing reliable and expandable storage options.

In summary, Marge serves as a robust NAS solution with Samba for seamless file sharing, Pihole with Unbound for network-wide ad-blocking, and WireGuard VPN for secure remote access. Together, these services create a reliable and secure storage environment while enhancing privacy and accessibility within my homelab setup.

## Setup Guide

### Prerequisites

Depending on the server you want to set up, different environment variables need to be added to the `.env` file.
This file must be placed in the `provisioning` directory.

#### Homer

Homer requires the following environment variables to be set:

```bash
# Network configuration
NETWORK_INTERFACE=                      # e.g. "eth0"
HOMER_IP_ADDRESS=                       # e.g. "192.168.0.2"
MARGE_IP_ADDRESS=                       # e.g. "192.168.0.3"
SUBNET_MASK_CIDR=                       # e.g. "24"
DEFAULT_GATEWAY=                        # e.g. "192.168.0.1"
DNS_SERVER=                             # e.g. "1.1.1.1"

# Host configuration
HOST_NAME=                              # "homer" or "marge"
USER_NAME=                              # e.g. "homer"
USER_PASSWORD=                          # e.g. "password"

# Timezone configuration
TIMEZONE=                               # e.g. "Europe/Brussels"

# Server configuration
SERVER_DOMAIN=                          # e.g. "awesome-homelab.com"

# Grafana contact point
DISCORD_WEBHOOK_URL=                    # e.g. "https://discord.com/api/webhooks/..."
```

#### Marge

Marge requires the following environment variables to be set:

```bash
# Network configuration
NETWORK_INTERFACE=                      # e.g. "eth0"
HOMER_IP_ADDRESS=                       # e.g. "192.168.0.2"
MARGE_IP_ADDRESS=                       # e.g. "192.168.0.3"
SUBNET_MASK_CIDR=                       # e.g. "24"
DEFAULT_GATEWAY=                        # e.g. "192.168.0.1"
DNS_SERVER=                             # e.g. "1.1.1.1"

# Host configuration
HOST_NAME=                              # "homer" or "marge"
USER_NAME=                              # e.g. "marge"
USER_PASSWORD=                          # e.g. "password"

# Timezone configuration
TIMEZONE=                               # e.g. "Europe/Brussels"

# Pi-hole configuration
PIHOLE_PASSWORD=                        # e.g. "password"

# WireGuard configuration
PUBLIC_IP_ADDRESS=                      # e.g. "209.141.217.63" (https://www.whatismyip.com/)
```

### Installation

To install the server, navigate to the `provisioning` directory and run the `init.sh` script.

#### Homer

```console
# cd provisioning
# ./init.sh
```

**Note:** The script **must** be run as root (`sudo -i`).

#### Marge

In case you want to install Marge, you'll have to run the `install.sh` script located in the `rockpi-sata` directory first.
Simply navigate to the `rockpi-sata` directory and run the `install.sh` script.

```console
# cd rockpi-sata
# ./install.sh
# systemctl reboot
```

After the installation of the SATA HAT, navigate back to the `provisioning` directory and run the `init.sh` script.

```console
# cd provisioning
# ./init.sh
```

**Note:** The script **must** be run as root (`sudo -i`).

## Contributing

Feel free to contribute to this repository by submitting pull requests with improvements, bug fixes, or additional server configurations.
Your contributions are highly appreciated!

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## References

-   [Raxda Rock Pi SATA HAT Documentation](https://wiki.radxa.com/Dual_Quad_SATA_HAT)
