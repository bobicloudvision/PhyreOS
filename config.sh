#!/bin/bash

# PhyreOS Configuration File

# Определяне на версии и директории
KERNEL_VERSION=$(curl -s https://www.kernel.org/releases.json | jq -r '.latest_stable.version')
WORKDIR="phyre_os"
ISODIR="$WORKDIR/iso"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v$(echo $KERNEL_VERSION | cut -d'.' -f1).x/linux-${KERNEL_VERSION}.tar.xz"
BUSYBOX_VERSION="1.35.0"  # Можете да актуализирате версията, ако е необходимо
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

# ISO output filename
ISO_NAME="phyre-os-${KERNEL_VERSION}.iso"

# APT Configuration
APT_VERSION="2.2.4"
LIBAPT_PKG_VERSION="6.0"
DEBIAN_RELEASE="bullseye" # Debian 11 codename

# APT Repository Configuration
REPO_NAME="PhyreOS Repository"
REPO_URL="http://phyreos.repo/packages"
REPO_CODENAME="stable"
REPO_COMPONENTS="main"
REPO_ARCH="amd64"
