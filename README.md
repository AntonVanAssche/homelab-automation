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

Homer serves as a versatile server hosting a variety of services, contributing to the functionality and management of the homelab. It acts as a central dashboard for monitoring and managing various aspects of the infrastructure.

Some of the services provided by Homer include:

-   Emby: A media server for organizing and streaming media content within the local network.
-   Pi-hole: A network-wide ad-blocking solution that improves internet browsing experience and enhances network security.
-   WireGuard VPN: A secure and efficient VPN solution for remote access to the homelab network.

## Server: Marge

<img src="https://cdn.shopify.com/s/files/1/0021/1497/7894/products/2020428_6_1024x1024.jpg?v=1600062159" alt="img" align="right" width="250px">

Marge is a dedicated Network-Attached Storage (NAS) server configured with a RAID 5 array using four SATA HDDs. It offers reliable data storage and access within the homelab environment.

This is made possible by using the Raxda Rock Pi SATA HAT, which allows for the connection of up to four SATA devices to a single Raspberry Pi. The SATA HAT is connected to the Raspberry Pi via the GPIO pins, and the SATA devices are connected to the SATA HAT via SATA cables.

Key features of Marge include:

-   Samba: A file-sharing service that allows seamless access to shared files within the local network.
-   RAID 5: A data storage technology that provides redundancy and fault tolerance to the homelab storage system.

## Contributing

Feel free to contribute to this repository by submitting pull requests with improvements, bug fixes, or additional server configurations. Your contributions are highly appreciated!

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
