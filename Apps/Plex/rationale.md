# Plex Configuration Rationale

This document explains the rationale behind specific configuration settings for the Plex app.

## Network Mode: Host Usage

Plex uses `network_mode: host` for the following reasons:

**Automatic Server Discovery**: Plex clients (mobile apps, Smart TVs, streaming devices) automatically discover the server on the local network through mDNS/Bonjour protocols, which require host network mode to function properly.

**DLNA Functionality**: Enables direct media streaming to DLNA-compatible devices like Smart TVs and game consoles through multicast UDP communication and standard UPnP/DLNA discovery protocols.

**Simplified Port Management**: Plex dynamically uses multiple ports for various features including GDM network discovery (UDP 32410-32414), Plex Companion integration (ports 3005, 8324), and automatic remote access configuration.

**Performance Optimization**: Eliminates NAT overhead from bridge networks, providing direct network access and better streaming performance for large media files.

## Hardware Acceleration

**GPU Device Mapping**: The `/dev/dri:/dev/dri` device mapping enables hardware-accelerated transcoding via Intel Quick Sync, AMD VCE, or NVIDIA NVENC, significantly reducing CPU usage and power consumption while supporting more concurrent streams.

## Authentication

Authentication is directly managed by Plex itself. The application provides its own built-in user management system with secure login functionality, including:
* Plex account integration via PLEX_CLAIM token
* Multi-user support with individual libraries
* Remote access authentication
* Parental controls and user permissions

No additional authentication layer is required as Plex handles all security aspects internally through its web interface and account system.

## Resource Limits

**Memory Limit (1GB)**: Sufficient for typical transcoding operations while preventing OOM conditions and ensuring system stability when sharing resources with other applications.

**CPU Shares (100)**: Provides fair distribution of CPU resources with other applications while maintaining overall system responsiveness.