#!/bin/bash

set -e

# Function to install dependencies based on distribution
install_dependencies() {
    echo "📦 Installing dependencies..."
    if [ -f /etc/redhat-release ]; then
        sudo dnf groupinstall -y "Development Tools"
        sudo dnf install -y gcc make flex bison openssl-devel bc elfutils-libelf-devel  \
            ncurses-devel xz jq wget cpio xorriso grub2-tools-extra gettext \
            perl-Pod-Html
        sudo dnf install -y glibc-devel glibc-static
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

# Load configuration file
CURRENT_DIR=$(pwd)
source $CURRENT_DIR/config.sh || { echo "❌ Failed to load configuration file!"; exit 1; }

# check if the KERNEL_VERSION is set
if [ -z "$KERNEL_VERSION" ]; then
    echo "❌ KERNEL_VERSION is not set in config.sh!"
    exit 1
fi

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

    cp $WORKDIR/src/linux-*/arch/x86/boot/bzImage $ISODIR/boot/vmlinuz

    # Verify kernel image was created
    if [ ! -f "$ISODIR/boot/vmlinuz" ]; then
        echo "❌ Failed to create kernel image!"
        exit 1
    else
        echo "✅ Kernel image created successfully: $(du -h "$ISODIR/boot/vmlinuz" | cut -f1)"
    fi
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
    sed -i 's/CONFIG_FEATURE_INSTALLER=y/CONFIG_FEATURE_INSTALLER=n/' .config
    sed -i 's/CONFIG_INSTALL_APPLET_SYMLINKS=y/CONFIG_INSTALL_APPLET_SYMLINKS=n/' .config

    sed -i 's/CONFIG_STATIC_LIBGCC=n/CONFIG_STATIC_LIBGCC=y/' .config
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

    echo "🛠️ Compiling BusyBox..."
    make clean
    make -j$(nproc)
    make -s CONFIG_PREFIX="$ISODIR" CONFIG_FEATURE_TC=n install
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
    mkdir -p "$WORKDIR/apt_packages"
    cd "$WORKDIR/apt_packages"
    
    # Create a temporary directory for package lists
    mkdir -p "$WORKDIR/apt_lists"
    cd "$WORKDIR/apt_lists"
    
    # Download package lists for the stable release with retry
    echo "📋 Downloading package lists..."
    wget --tries=3 --timeout=15 --waitretry=5 "$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/binary-amd64/Packages.gz"
    
    # Check if download was successful
    if [ ! -f "Packages.gz" ]; then
        echo "❌ Failed to download package lists. Trying alternative mirror..."
        DEBIAN_MIRROR="http://ftp.us.debian.org/debian" # Fallback mirror
        wget --tries=3 --timeout=15 --waitretry=5 "$DEBIAN_MIRROR/dists/$DEBIAN_RELEASE/main/binary-amd64/Packages.gz"
        
        if [ ! -f "Packages.gz" ]; then
            echo "❌ Failed to download package lists from alternative mirror. Exiting."
            exit 1
        fi
    fi
    
    gunzip -f Packages.gz
    
    # Function to extract latest package URL
    get_package_url() {
        local package_name="$1"
        grep -A 20 "Package: $package_name$" Packages | grep "Filename:" | head -1 | awk '{print $2}'
    }
    
    # Get URLs for required packages
    APT_URL=$(get_package_url "apt")
    APT_UTILS_URL=$(get_package_url "apt-utils")
    LIBAPT_PKG_URL=$(get_package_url "libapt-pkg6.0")
    if [ -z "$LIBAPT_PKG_URL" ]; then
        LIBAPT_PKG_URL=$(get_package_url "libapt-pkg5.0")
    fi
    if [ -z "$LIBAPT_PKG_URL" ]; then
        LIBAPT_PKG_URL=$(get_package_url "libapt-pkg")
    fi
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
    
    # Function to download package with retry
    download_package() {
        local url="$1"
        local output="$2"
        local max_retries=3
        local retry=0
        local success=false
        
        while [ $retry -lt $max_retries ] && [ "$success" = false ]; do
            echo "Downloading $output (attempt $((retry+1))/$max_retries)..."
            wget --tries=3 --timeout=15 --waitretry=5 "$DEBIAN_MIRROR/$url" -O "$output"
            
            # Verify the package
            if [ -f "$output" ] && [ $(stat -c%s "$output") -gt 1000 ]; then
                echo "✅ Successfully downloaded $output"
                success=true
            else
                echo "⚠️ Download failed or file too small. Retrying..."
                rm -f "$output"
                retry=$((retry+1))
            fi
        done
        
        if [ "$success" = false ]; then
            echo "❌ Failed to download $output after $max_retries attempts."
            return 1
        fi
        
        return 0
    }
    
    # Download packages
    mkdir -p "$WORKDIR/apt_packages"
    cd "$WORKDIR/apt_packages"
    echo "⬇️ Downloading APT and dependencies..."
    
    # Core APT packages
    download_package "$APT_URL" "apt.deb" || exit 1
    download_package "$APT_UTILS_URL" "apt-utils.deb" || exit 1
    download_package "$LIBAPT_PKG_URL" "libapt-pkg.deb" || exit 1
    
    # Dependencies
    download_package "$LIBC6_URL" "libc6.deb" || exit 1
    download_package "$LIBSTDCPP6_URL" "libstdc++6.deb" || exit 1
    download_package "$LIBGCC_URL" "libgcc-s1.deb" || exit 1
    download_package "$ZLIB_URL" "zlib1g.deb" || exit 1
    download_package "$LIBBZ2_URL" "libbz2.deb" || exit 1
    download_package "$LIBLZ4_URL" "liblz4.deb" || exit 1
    download_package "$LIBLZMA_URL" "liblzma.deb" || exit 1
    download_package "$LIBZSTD_URL" "libzstd.deb" || exit 1
    download_package "$LIBSELINUX_URL" "libselinux.deb" || exit 1
    download_package "$LIBSYSTEMD_URL" "libsystemd.deb" || exit 1
    download_package "$LIBGCRYPT_URL" "libgcrypt.deb" || exit 1
    
    # Verify all downloaded packages
    echo "📋 Verifying downloaded packages..."
    for pkg in *.deb; do
        if [ -f "$pkg" ]; then
            pkg_size=$(stat -c%s "$pkg")
            echo "Package $pkg size: $pkg_size bytes"
            
            # Basic size check (most .deb packages should be at least 10KB)
            if [ $pkg_size -lt 10000 ]; then
                echo "⚠️ Warning: $pkg is suspiciously small ($pkg_size bytes)"
            fi
        fi
    done
}

# Function to extract APT packages
extract_apt_packages() {
    echo "📦 Extracting APT packages..."
    APT_PACKAGES_PATH="$WORKDIR/apt_packages"
    mkdir -p $APT_PACKAGES_PATH
    cd $APT_PACKAGES_PATH

    # Install required tools if missing
    command -v ar &>/dev/null || sudo dnf install -y binutils
    command -v xz &>/dev/null || sudo dnf install -y xz
    
    # Extract all .deb packages
    echo "Using ar + tar for extraction..."
    for pkg in *.deb; do
        [ -f "$pkg" ] || continue
        
        echo "Extracting $pkg..."
        mkdir -p "extract_$pkg"
        cd "extract_$pkg"
        
        # Extract with ar
        ar x "../$pkg" 2>/dev/null || { echo "⚠️ ar extraction failed for $pkg."; cd ..; continue; }
        
        # Find and extract data.tar.* based on extension
        DATA_TAR=$(ls data.tar.* 2>/dev/null || echo "")
        if [ -z "$DATA_TAR" ]; then
            echo "⚠️ No data.tar.* found in $pkg"
            cd ..
            continue
        fi
        
        # Extract based on compression type
        case "$DATA_TAR" in
            data.tar.xz)
                tar xf "$DATA_TAR"
                ;;
            data.tar.gz)
                tar xzf "$DATA_TAR"
                ;;
            data.tar.bz2)
                tar xjf "$DATA_TAR"
                ;;
            data.tar.zst)
                command -v zstd &>/dev/null || sudo dnf install -y zstd
                zstd -d "$DATA_TAR" -o data.tar && tar xf data.tar && rm data.tar
                ;;
            data.tar)
                tar xf "$DATA_TAR"
                ;;
            *)
                echo "⚠️ Unknown compression format: $DATA_TAR"
                ;;
        esac
        
        cd ..
    done
    
    # Verify extraction results
    echo "📋 Verifying extraction results..."
    for extract_dir in extract_*; do
        [ -d "$extract_dir" ] || continue
        
        file_count=$(find "$extract_dir" -type f | wc -l)
        echo "$extract_dir contains $file_count files"
#        [ $file_count -eq 0 ] && echo "⚠️ Warning: No files extracted in $extract_dir"
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

}

# Function to set up repository structure
setup_repository() {
    echo "📦 Creating package repository structure..."
    mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"
    mkdir -p "$WORKDIR/repo/pool/main"

    # Export variables for the template
    export REPO_NAME
    export REPO_URL
    export REPO_CODENAME
    export REPO_COMPONENTS
    export REPO_ARCH
    
    # Create repository metadata using template
    echo "📦 Creating repository metadata..."
    envsubst < $CURRENT_DIR/release.template > "$WORKDIR/repo/dists/stable/main/binary-amd64/Release"
    
    # Verify template substitution
    echo "Verifying Release file..."
    if grep -q '\$[A-Z_]\+' "$WORKDIR/repo/dists/stable/main/binary-amd64/Release"; then
        echo "⚠️ Warning: Some variables were not substituted in Release file"
        grep '\$[A-Z_]\+' "$WORKDIR/repo/dists/stable/main/binary-amd64/Release"
    else
        echo "✅ Release file created successfully"
    fi
    
    # Also create the main Release file
    envsubst < $CURRENT_DIR/release.template > "$WORKDIR/repo/dists/stable/Release"
}

# Function to create initrd image
create_initrd_image() {
    echo "📦 Creating initrd image..."
    
    # Copy init script
    echo "📋 Copying init script..."
    cp $CURRENT_DIR/init.sh "$WORKDIR/initrd/init"
    
    # Ensure init script has correct permissions
    echo "🔒 Setting init script permissions..."
    chmod 755 "$WORKDIR/initrd/init"
    
    # Verify init script exists and is executable
    if [ ! -x "$WORKDIR/initrd/init" ]; then
        echo "❌ Init script is not executable or doesn't exist!"
        exit 1
    else
        echo "✅ Init script is ready"
    fi
    
    # Add busybox to initrd if not already included
    if [ ! -f "$WORKDIR/initrd/bin/busybox" ] && [ -f "$ISODIR/bin/busybox" ]; then
        echo "📦 Copying BusyBox to initrd..."
        mkdir -p "$WORKDIR/initrd/bin"
        cp "$ISODIR/bin/busybox" "$WORKDIR/initrd/bin/"
        chmod 755 "$WORKDIR/initrd/bin/busybox"
    fi
    
    # Create essential directories
    mkdir -p "$WORKDIR/initrd/dev"
    mkdir -p "$WORKDIR/initrd/proc"
    mkdir -p "$WORKDIR/initrd/sys"
    mkdir -p "$WORKDIR/initrd/tmp"
    mkdir -p "$WORKDIR/initrd/bin"
    mkdir -p "$WORKDIR/initrd/sbin"
    
    echo "📦 Creating initrd image..."
    ( cd "$WORKDIR/initrd" && find . | cpio -H newc -o ) | gzip -9 > "$ISODIR/boot/initrd.img"
    
    # Verify initrd was created
    if [ ! -f "$ISODIR/boot/initrd.img" ]; then
        echo "❌ Failed to create initrd image!"
        exit 1
    else
        echo "✅ Initrd image created successfully: $(du -h "$ISODIR/boot/initrd.img" | cut -f1)"
    fi
}

# Function to create GRUB configuration
create_grub_config() {
    echo "⚙️ Creating GRUB configuration..."
    
    # Export all variables needed by the template
    export KERNEL_VERSION
    export BUSYBOX_VERSION
    export REPO_NAME
    export REPO_URL
    export REPO_CODENAME
    export REPO_COMPONENTS
    export REPO_ARCH
    
    # Use envsubst to properly expand variables in the template
    envsubst < $CURRENT_DIR/grub.cfg.template > "$ISODIR/boot/grub/grub.cfg"
    
    # Check if variables were properly substituted
    echo "Verifying GRUB configuration..."
    if grep -q '\$[A-Z_]\+' "$ISODIR/boot/grub/grub.cfg"; then
        echo "⚠️ Warning: Some variables were not substituted in grub.cfg"
        grep '\$[A-Z_]\+' "$ISODIR/boot/grub/grub.cfg"
    else
        echo "✅ GRUB configuration created successfully"
    fi
}

# Function to create rootfs
create_rootfs() {
    echo "🌱 Creating root filesystem..."
    
    # Create rootfs directory structure
    mkdir -p "$WORKDIR/rootfs"
    mkdir -p "$WORKDIR/rootfs/bin"
    mkdir -p "$WORKDIR/rootfs/sbin"
    mkdir -p "$WORKDIR/rootfs/etc"
    mkdir -p "$WORKDIR/rootfs/etc/apt"
    mkdir -p "$WORKDIR/rootfs/etc/apt/sources.list.d"
    mkdir -p "$WORKDIR/rootfs/dev"
    mkdir -p "$WORKDIR/rootfs/proc"
    mkdir -p "$WORKDIR/rootfs/sys"
    mkdir -p "$WORKDIR/rootfs/tmp"
    mkdir -p "$WORKDIR/rootfs/usr/bin"
    mkdir -p "$WORKDIR/rootfs/usr/sbin"
    mkdir -p "$WORKDIR/rootfs/usr/lib"
    mkdir -p "$WORKDIR/rootfs/var/lib/apt/lists"
    mkdir -p "$WORKDIR/rootfs/var/cache/apt/archives"
    mkdir -p "$WORKDIR/rootfs/lib"
    mkdir -p "$WORKDIR/rootfs/lib64"
    mkdir -p "$WORKDIR/rootfs/home"
    mkdir -p "$WORKDIR/rootfs/root"
    mkdir -p "$WORKDIR/rootfs/mnt"
    mkdir -p "$WORKDIR/rootfs/opt"
    
    # Copy BusyBox to rootfs
    echo "📦 Copying BusyBox to rootfs..."
    if [ -f "$ISODIR/bin/busybox" ]; then
        cp "$ISODIR/bin/busybox" "$WORKDIR/rootfs/bin/"
    else
        echo "⚠️ BusyBox binary not found in $ISODIR/bin/"
    fi
    
    # Copy APT and libraries to rootfs
    echo "📦 Copying APT to rootfs..."
    cp -a "$WORKDIR/initrd/usr/bin/apt"* "$WORKDIR/rootfs/usr/bin/" 2>/dev/null || true
    cp -a "$WORKDIR/initrd/usr/lib/apt" "$WORKDIR/rootfs/usr/lib/" 2>/dev/null || true
    cp -a "$WORKDIR/initrd/usr/lib/x86_64-linux-gnu" "$WORKDIR/rootfs/usr/lib/" 2>/dev/null || true
    cp -a "$WORKDIR/initrd/lib/"* "$WORKDIR/rootfs/lib/" 2>/dev/null || true
    cp -a "$WORKDIR/initrd/lib64/"* "$WORKDIR/rootfs/lib64/" 2>/dev/null || true
    
    # Set up APT configuration
    echo "⚙️ Setting up APT configuration..."
    cat > "$WORKDIR/rootfs/etc/apt/sources.list" << EOF
# PhyreOS custom repository
deb [trusted=yes] http://phyreos.repo/packages stable main
EOF

    # Set up APT preferences
    cat > "$WORKDIR/rootfs/etc/apt/preferences" << EOF
Package: *
Pin: origin phyreos.repo
Pin-Priority: 900
EOF

    # Create basic configuration files
    echo "⚙️ Creating basic configuration files..."
    
    # /etc/fstab
    cat > "$WORKDIR/rootfs/etc/fstab" << EOF
# /etc/fstab: static file system information
proc            /proc           proc    defaults        0       0
sysfs           /sys            sysfs   defaults        0       0
devtmpfs        /dev            devtmpfs defaults      0       0
tmpfs           /tmp            tmpfs   defaults        0       0
EOF

    # /etc/hostname
    echo "phyreos" > "$WORKDIR/rootfs/etc/hostname"
    
    # /etc/hosts
    cat > "$WORKDIR/rootfs/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   phyreos

# The following lines are desirable for IPv6 capable hosts
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    # /etc/passwd
    cat > "$WORKDIR/rootfs/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

    # /etc/group
    cat > "$WORKDIR/rootfs/etc/group" << EOF
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:
dip:x:30:
www-data:x:33:
backup:x:34:
operator:x:37:
list:x:38:
irc:x:39:
src:x:40:
gnats:x:41:
shadow:x:42:
utmp:x:43:
video:x:44:
sasl:x:45:
plugdev:x:46:
staff:x:50:
games:x:60:
users:x:100:
nogroup:x:65534:
EOF

    # /etc/shadow with locked root password
    cat > "$WORKDIR/rootfs/etc/shadow" << EOF
root:*:19000:0:99999:7:::
daemon:*:19000:0:99999:7:::
bin:*:19000:0:99999:7:::
sys:*:19000:0:99999:7:::
sync:*:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
EOF

    # Create a simple init script for the rootfs
    cat > "$WORKDIR/rootfs/sbin/init" << EOF
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Set hostname
hostname \$(cat /etc/hostname)

# Start system initialization
echo "PhyreOS starting..."

# Start a login shell
exec /bin/sh
EOF
    chmod 755 "$WORKDIR/rootfs/sbin/init"
    
    # Create rootfs archive
    echo "📦 Creating rootfs archive..."
    cd "$WORKDIR"
    tar -czf "$ISODIR/boot/rootfs.tar.gz" -C "$WORKDIR/rootfs" .
    
    # Verify rootfs archive was created
    if [ ! -f "$ISODIR/boot/rootfs.tar.gz" ]; then
        echo "❌ Failed to create rootfs archive!"
        exit 1
    else
        echo "✅ Rootfs archive created successfully: $(du -h "$ISODIR/boot/rootfs.tar.gz" | cut -f1)"
    fi
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
#    install_dependencies
#    prepare_directories
#    build_kernel
    build_busybox
    create_initrd_structure
    download_apt_packages
    extract_apt_packages
    copy_apt_to_initrd
    setup_repository
    create_initrd_image
    create_rootfs
    create_grub_config
    generate_iso
}

# Run the main function
main
