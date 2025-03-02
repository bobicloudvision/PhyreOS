#!/bin/bash

set -e

CURRENT_DIR=$(pwd)

# Load configuration file
source $CURRENT_DIR/config.sh

# Function to install dependencies based on distribution
install_dependencies() {
    echo "📦 Installing dependencies..."
    if [ -f /etc/redhat-release ]; then
        sudo dnf groupinstall -y "Development Tools"
        sudo dnf install -y gcc make flex bison openssl-devel bc elfutils-libelf-devel \
            ncurses-devel xz jq wget cpio xorriso grub2-tools-extra gettext
    elif [ -f /etc/debian_version ]; then
        sudo apt update
        sudo apt install -y build-essential flex bison libssl-dev bc libelf-dev \
            libncurses-dev xz-utils jq wget cpio xorriso grub-pc-bin grub-common gettext-base
    else
        echo "⚠️ Unsupported distribution!"
        exit 1
    fi
}

# Function to prepare working directories
prepare_directories() {
    echo "🗂️ Preparing working directories..."
    rm -rf "$WORKDIR"
    mkdir -p "$ISODIR/boot/grub"
    mkdir -p "$WORKDIR/src"
}

# Function to build the Linux kernel
build_kernel() {
    echo "⬇️ Downloading Linux kernel version $KERNEL_VERSION..."
    cd "$WORKDIR/src"

    if ! wget -c "$KERNEL_URL" -O "linux.tar.xz"; then
        echo "❌ Failed to download kernel!"
        exit 1
    fi

    tar -xf linux.tar.xz
    cd linux-*/

    echo "🛠️ Compiling kernel..."
    make defconfig
    make -j$(nproc)

    sleep 10  # Wait to avoid errors when creating ISO image

    cp $WORKDIR/src/linux-*/arch/x86/boot/bzImage $ISODIR/boot/vmlinuz
}

# Function to build BusyBox
build_busybox() {
    echo "⬇️ Downloading BusyBox version $BUSYBOX_VERSION..."
    cd "$WORKDIR/src"
    if ! wget -c "$BUSYBOX_URL" -O "busybox.tar.bz2"; then
        echo "❌ Failed to download BusyBox!"
        exit 1
    fi

    tar -xjf busybox.tar.bz2
    cd busybox-${BUSYBOX_VERSION}

    echo "🛠️ Compiling BusyBox..."
    make defconfig
    make -j$(nproc)
    make install CONFIG_PREFIX="$ISODIR"
}

# Function to create initrd directory structure
create_initrd_structure() {
    echo "📦 Creating initrd structure..."
    mkdir -p "$WORKDIR/initrd"
    mkdir -p "$WORKDIR/initrd/etc/apt"
    mkdir -p "$WORKDIR/initrd/var/lib/apt/lists"
    mkdir -p "$WORKDIR/initrd/var/cache/apt/archives"
    mkdir -p "$WORKDIR/initrd/usr/bin"
    mkdir -p "$WORKDIR/initrd/usr/lib"
    mkdir -p "$WORKDIR/initrd/lib"
    mkdir -p "$WORKDIR/initrd/lib64"
    mkdir -p "$WORKDIR/apt_packages"
}

# Function to download APT packages
download_apt_packages() {
    echo "⬇️ Downloading APT packages from Debian repository..."
    cd "$WORKDIR/apt_packages"
    
    # Define Debian mirror
    DEBIAN_MIRROR="http://ftp.debian.org/debian"
    
    # Core APT packages
    wget -c "$DEBIAN_MIRROR/pool/main/a/apt/apt_${APT_VERSION}_amd64.deb"
    wget -c "$DEBIAN_MIRROR/pool/main/a/apt/apt-utils_${APT_VERSION}_amd64.deb"
    wget -c "$DEBIAN_MIRROR/pool/main/a/apt/libapt-pkg${LIBAPT_PKG_VERSION}_${APT_VERSION}_amd64.deb"
    
    # Dependencies for Debian Bullseye (11)
    if [ "$DEBIAN_RELEASE" = "bullseye" ]; then
        wget -c "$DEBIAN_MIRROR/pool/main/g/glibc/libc6_2.31-13+deb11u5_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/g/gcc-10/libstdc++6_10.2.1-6_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/g/gcc-10/libgcc-s1_10.2.1-6_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/z/zlib/zlib1g_1.2.11.dfsg-2+deb11u2_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/b/bzip2/libbz2-1.0_1.0.8-4_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/l/lz4/liblz4-1_1.9.3-2_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/x/xz-utils/liblzma5_5.2.5-2.1~deb11u1_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/libz/libzstd/libzstd1_1.4.8+dfsg-2.1_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/g/glibc/libselinux1_3.1-3_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/g/glibc/libsystemd0_247.3-7+deb11u2_amd64.deb"
        wget -c "$DEBIAN_MIRROR/pool/main/g/glibc/libgcrypt20_1.8.7-6_amd64.deb"
    else
        # For other Debian releases, you would add appropriate package versions here
        echo "⚠️ Warning: Using Debian $DEBIAN_RELEASE, package versions may need adjustment"
    fi
}

# Function to extract APT packages
extract_apt_packages() {
    echo "📦 Extracting APT packages..."
    cd "$WORKDIR/apt_packages"
    for pkg in *.deb; do
        echo "Extracting $pkg..."
        mkdir -p "extract_$pkg"
        cd "extract_$pkg"
        ar x "../$pkg"
        tar xf data.tar.* --strip-components=1
        cd ..
    done
}

# Function to copy APT files to initrd
copy_apt_to_initrd() {
    echo "📦 Copying APT binaries and libraries to initrd..."
    cd "$WORKDIR/apt_packages"
    
    # Copy APT binaries and libraries
    cp -a extract_apt_*/usr/bin/apt* "$WORKDIR/initrd/usr/bin/"
    cp -a extract_apt_*/usr/lib/apt "$WORKDIR/initrd/usr/lib/"
    cp -a extract_libapt-pkg*/usr/lib/x86_64-linux-gnu/* "$WORKDIR/initrd/usr/lib/"

    # Copy required shared libraries
    echo "📦 Copying shared libraries..."
    for extract_dir in extract_*; do
        if [ -d "$extract_dir/lib" ]; then
            cp -a "$extract_dir/lib/"* "$WORKDIR/initrd/lib/" 2>/dev/null || true
        fi
        if [ -d "$extract_dir/lib64" ]; then
            cp -a "$extract_dir/lib64/"* "$WORKDIR/initrd/lib64/" 2>/dev/null || true
        fi
        if [ -d "$extract_dir/usr/lib" ]; then
            cp -a "$extract_dir/usr/lib/"* "$WORKDIR/initrd/usr/lib/" 2>/dev/null || true
        fi
        if [ -d "$extract_dir/usr/lib/x86_64-linux-gnu" ]; then
            mkdir -p "$WORKDIR/initrd/usr/lib/x86_64-linux-gnu"
            cp -a "$extract_dir/usr/lib/x86_64-linux-gnu/"* "$WORKDIR/initrd/usr/lib/x86_64-linux-gnu/" 2>/dev/null || true
        fi
    done
}

# Function to set up repository structure
setup_repository() {
    echo "📦 Creating package repository structure..."
    mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"
    mkdir -p "$WORKDIR/repo/pool/main"

    # Create repository metadata
    echo "📦 Creating repository metadata..."
    cat > "$WORKDIR/repo/dists/stable/main/binary-amd64/Release" << EOF
Archive: stable
Component: main
Origin: PhyreOS
Label: PhyreOS Custom Repository
Architecture: amd64
EOF
}

# Function to create initrd image
create_initrd_image() {
    echo "📦 Creating initrd image..."
    
    # Copy init script
    cp $CURRENT_DIR/init.sh "$WORKDIR/initrd/init"
    chmod +x "$WORKDIR/initrd/init"

    # Create the initrd image
    ( cd "$WORKDIR/initrd" && find . | cpio -o --format=newc ) | gzip > "$ISODIR/boot/initrd.img"
}

# Function to create GRUB configuration
create_grub_config() {
    echo "⚙️ Creating GRUB configuration..."
    # Use envsubst to properly expand variables in the template
    envsubst < $CURRENT_DIR/grub.cfg.template > "$ISODIR/boot/grub/grub.cfg"
}

# Function to generate ISO image
generate_iso() {
    echo "📀 Generating ISO image: $ISO_NAME..."
    cd "$CURRENT_DIR"
    grub2-mkrescue -o "$ISO_NAME" "$ISODIR"
    echo "✅ ISO image is ready: $ISO_NAME"
}

# Main execution flow
main() {
    install_dependencies
    prepare_directories
    build_kernel
    build_busybox
    create_initrd_structure
    download_apt_packages
    extract_apt_packages
    copy_apt_to_initrd
    setup_repository
    create_initrd_image
    create_grub_config
    generate_iso
}

# Run the main function
main
