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
