#!/bin/bash

# PhyreOS Configuration File

# Определяне на версии и директории
CURRENT_DIR=$(pwd)
KERNEL_VERSION=$(curl -s https://www.kernel.org/releases.json | jq -r '.latest_stable.version')
WORKDIR="$CURRENT_DIR/phyre_os"
ISODIR="$WORKDIR/iso"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v$(echo $KERNEL_VERSION | cut -d'.' -f1).x/linux-${KERNEL_VERSION}.tar.xz"
BUSYBOX_VERSION="1.35.0"  # Можете да актуализирате версията, ако е необходимо
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

# ISO output filename
ISO_NAME="phyre-os-${KERNEL_VERSION}.iso"

# APT Configuration
DEBIAN_RELEASE="stable" # Use stable instead of specific release name
DEBIAN_MIRROR="http://deb.debian.org/debian" # Use the most reliable Debian mirror

# Debian Repository Configuration
DEBIAN_MIRROR="http://deb.debian.org/debian"

# APT Repository Configuration
REPO_NAME="PhyreOS Repository"
REPO_URL="http://phyreos.repo/packages"
REPO_CODENAME="stable"
REPO_COMPONENTS="main"
REPO_ARCH="amd64"
