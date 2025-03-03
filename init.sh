#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Function to setup basic environment
setup_basic_env() {
    # Create necessary directories
    mkdir -p /etc/apt/sources.list.d
    mkdir -p /var/lib/apt/lists
    mkdir -p /var/cache/apt/archives

    # Set up APT configuration
    cat > /etc/apt/sources.list << EOF
# PhyreOS custom repository
deb [trusted=yes] http://phyreos.repo/packages stable main
EOF

    # Set up APT preferences for PhyreOS packages
    cat > /etc/apt/preferences << EOF
Package: *
Pin: origin phyreos.repo
Pin-Priority: 900
EOF
}

# Check if we're booting with rootfs
if grep -q "rootfstype=tmpfs" /proc/cmdline; then
    echo "Booting with rootfs..."
    
    # Create mount point for rootfs
    mkdir -p /mnt/rootfs
    
    # Mount tmpfs for rootfs
    mount -t tmpfs -o size=512M none /mnt/rootfs
    
    # Check if rootfs archive exists
    if [ -f /boot/rootfs.tar.gz ]; then
        echo "Extracting rootfs..."
        tar -xzf /boot/rootfs.tar.gz -C /mnt/rootfs
        
        # Prepare for switch_root
        mkdir -p /mnt/rootfs/oldroot
        
        # Mount essential filesystems in new root
        mount -t proc none /mnt/rootfs/proc
        mount -t sysfs none /mnt/rootfs/sys
        mount -t devtmpfs none /mnt/rootfs/dev
        
        # Switch to the new root
        echo "Switching to rootfs..."
        exec switch_root /mnt/rootfs /sbin/init
    else
        echo "Error: rootfs.tar.gz not found!"
        echo "Falling back to initrd..."
    fi
fi

# If we're here, we're either using initrd or rootfs extraction failed
echo "Booting with initrd..."

# Setup basic environment
setup_basic_env

# Initialize APT
apt-get update

echo "PhyreOS initialized with APT package manager"
echo "Type 'apt-get install <package>' to install packages"
echo "Type 'apt-get update' to update package lists"

# Drop to shell
exec /bin/sh
