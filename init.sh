#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

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

# Initialize APT
apt-get update

echo "PhyreOS initialized with APT package manager"
echo "Type 'apt-get install <package>' to install packages"
echo "Type 'apt-get update' to update package lists"

# Drop to shell
exec /bin/sh
