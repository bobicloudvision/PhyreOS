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
            ncurses-devel xz jq wget cpio xorriso grub2-tools-extra gettext \
            perl-Pod-Html
    elif [ -f /etc/debian_version ]; then
        sudo apt update
        sudo apt install -y build-essential flex bison libssl-dev bc libelf-dev \
            libncurses-dev xz-utils jq wget cpio xorriso grub-pc-bin grub-common gettext-base \
            perl-doc
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

    echo "🛠️ Configuring BusyBox..."
    make defconfig
    
    # Disable problematic applets for AlmaLinux 9
    sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config
    
    echo "🛠️ Compiling BusyBox..."
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
    
    # Create a temporary directory for package lists
    mkdir -p "$WORKDIR/apt_lists"
    cd "$WORKDIR/apt_lists"
    
    # Download package lists for the stable release
    echo "📋 Downloading package lists..."
    wget -q "$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/binary-amd64/Packages.gz"
    gunzip -f Packages.gz
    
    # Function to extract latest package URL
    get_package_url() {
        local package_name="$1"
        grep -A 20 "Package: $package_name$" Packages | grep "Filename:" | head -1 | awk '{print $2}'
    }
    
    # Get URLs for required packages
    APT_URL=$(get_package_url "apt")
    APT_UTILS_URL=$(get_package_url "apt-utils")
    LIBAPT_PKG_URL=$(get_package_url "libapt-pkg")
    LIBC6_URL=$(get_package_url "libc6")
    LIBSTDCPP6_URL=$(get_package_url "libstdc++6")
    LIBGCC_URL=$(get_package_url "libgcc-s1")
    ZLIB_URL=$(get_package_url "zlib1g")
    LIBBZ2_URL=$(get_package_url "libbz2-1.0")
    LIBLZ4_URL=$(get_package_url "liblz4-1")
    LIBLZMA_URL=$(get_package_url "liblzma5")
    LIBZSTD_URL=$(get_package_url "libzstd1")
    LIBSELINUX_URL=$(get_package_url "libselinux1")
    LIBSYSTEMD_URL=$(get_package_url "libsystemd0")
    LIBGCRYPT_URL=$(get_package_url "libgcrypt20")
    
    # Download packages
    mkdir -p "$WORKDIR/apt_packages"
    cd "$WORKDIR/apt_packages"
    echo "⬇️ Downloading APT and dependencies..."
    
    # Core APT packages
    wget -c "$DEBIAN_MIRROR/$APT_URL" -O apt.deb
    wget -c "$DEBIAN_MIRROR/$APT_UTILS_URL" -O apt-utils.deb
    wget -c "$DEBIAN_MIRROR/$LIBAPT_PKG_URL" -O libapt-pkg.deb
    
    # Dependencies
    wget -c "$DEBIAN_MIRROR/$LIBC6_URL" -O libc6.deb
    wget -c "$DEBIAN_MIRROR/$LIBSTDCPP6_URL" -O libstdc++6.deb
    wget -c "$DEBIAN_MIRROR/$LIBGCC_URL" -O libgcc-s1.deb
    wget -c "$DEBIAN_MIRROR/$ZLIB_URL" -O zlib1g.deb
    wget -c "$DEBIAN_MIRROR/$LIBBZ2_URL" -O libbz2.deb
    wget -c "$DEBIAN_MIRROR/$LIBLZ4_URL" -O liblz4.deb
    wget -c "$DEBIAN_MIRROR/$LIBLZMA_URL" -O liblzma.deb
    wget -c "$DEBIAN_MIRROR/$LIBZSTD_URL" -O libzstd.deb
    wget -c "$DEBIAN_MIRROR/$LIBSELINUX_URL" -O libselinux.deb
    wget -c "$DEBIAN_MIRROR/$LIBSYSTEMD_URL" -O libsystemd.deb
    wget -c "$DEBIAN_MIRROR/$LIBGCRYPT_URL" -O libgcrypt.deb
}

# Function to extract APT packages
extract_apt_packages() {
    echo "📦 Extracting APT packages..."
    APT_PACKAGES_PATH="$WORKDIR/apt_packages"
    mkdir -p $APT_PACKAGES_PATH
    cd $APT_PACKAGES_PATH

    for pkg in *.deb; do
        echo "Extracting $pkg..."
        mkdir -p "extract_$pkg"
        cd "extract_$pkg"
        ar x "$APT_PACKAGES_PATH/$pkg"
        tar xf data.tar.* --strip-components=1
        cd ..
    done
}

# Function to copy APT files to initrd
copy_apt_to_initrd() {
    echo "📦 Copying APT binaries and libraries to initrd..."
    cd "$WORKDIR/apt_packages"
    
    # Copy APT binaries and libraries
    cp -a extract_apt.deb/usr/bin/apt* "$WORKDIR/initrd/usr/bin/" 2>/dev/null || true
    cp -a extract_apt.deb/usr/lib/apt "$WORKDIR/initrd/usr/lib/" 2>/dev/null || true
    cp -a extract_libapt-pkg.deb/usr/lib/x86_64-linux-gnu/* "$WORKDIR/initrd/usr/lib/" 2>/dev/null || true

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
    
    # Make sure all required directories exist in the initrd
    mkdir -p "$WORKDIR/initrd/usr/lib/x86_64-linux-gnu"
    
    # Create symlinks for compatibility if needed
    if [ ! -e "$WORKDIR/initrd/usr/bin/apt-get" ] && [ -e "$WORKDIR/initrd/usr/bin/apt" ]; then
        ln -sf apt "$WORKDIR/initrd/usr/bin/apt-get"
    fi
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
#    prepare_directories
#    build_kernel
#    build_busybox
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
