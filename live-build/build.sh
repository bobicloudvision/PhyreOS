#!/bin/bash

# Exit on error
set -e

# Define the build directory
BUILD_DIR=~/my-advanced-live-image

# Step 1: Install necessary dependencies
echo "Installing live-build and required dependencies..."
sudo apt update
sudo apt install -y live-build live-boot live-config debootstrap coreutils

# Step 2: Set up the build environment
echo "Setting up live-build environment..."
mkdir -p $BUILD_DIR
cd $BUILD_DIR
lb config

# Step 3: Add custom package list (e.g., GNOME, Vim, curl, etc.)
echo "Creating custom package list..."
mkdir -p config/package-lists
echo "vim
curl
htop
gnome-core
firefox-esr" > config/package-lists/my-desktop-packages.list.chroot

# Step 4: Add custom .bashrc for aliases
echo "Creating custom bashrc..."
mkdir -p config/includes.chroot/etc
echo "alias ll='ls -lah'" > config/includes.chroot/etc/bash.bashrc

# Step 5: Create custom user and password setup
echo "Creating custom user..."
mkdir -p config/hooks
echo '#!/bin/bash
adduser --disabled-password --gecos "" customuser
echo "customuser:password" | chpasswd' > config/hooks/01-create-user.chroot
chmod +x config/hooks/01-create-user.chroot

# Step 6: Set up custom MOTD (Message of the Day)
echo "Creating custom MOTD..."
echo "Welcome to my custom Debian live image!" > config/includes.chroot/etc/motd

# Step 7: Add custom desktop background (replace with your own image)
echo "Adding custom desktop background..."
mkdir -p config/includes.chroot/usr/share/backgrounds/
cp ~/my-background.jpg config/includes.chroot/usr/share/backgrounds/

# Step 8: Configure static IP (optional, modify as needed)
echo "Configuring static IP..."
echo "iface eth0 inet static
address 192.168.1.100
netmask 255.255.255.0
gateway 192.168.1.1" > config/includes.chroot/etc/network/interfaces

# Step 9: Configure DNS settings (optional, modify as needed)
echo "Configuring DNS..."
echo "nameserver 8.8.8.8" > config/includes.chroot/etc/resolv.conf

# Step 10: Enable persistence (optional, modify as needed)
echo "Enabling persistence..."
echo "persistence" > config/bootloaders/grub.cfg

# Step 11: Configure /etc/fstab for persistence (modify partition as needed)
echo "Setting up fstab for persistence..."
echo "/dev/sda1  /  ext4  defaults  0  1" > config/includes.chroot/etc/fstab

# Step 12: Mount necessary filesystems for chroot (if not already mounted)
echo "Mounting necessary filesystems for chroot..."
sudo mount --bind /dev $BUILD_DIR/chroot/dev
sudo mount --bind /proc $BUILD_DIR/chroot/proc
sudo mount --bind /sys $BUILD_DIR/chroot/sys
sudo mount --bind /run $BUILD_DIR/chroot/run

# Step 13: Ensure necessary binaries (like 'env') are available in the chroot
echo "Ensuring coreutils and env are available in the chroot..."
sudo chroot $BUILD_DIR/chroot /bin/bash -c "apt-get update && apt-get install -y coreutils"

# Step 14: Build the live image
echo "Building the live image..."
sudo lb build

# Step 15: Unmount filesystems after build is complete
echo "Unmounting filesystems..."
sudo umount $BUILD_DIR/chroot/dev
sudo umount $BUILD_DIR/chroot/proc
sudo umount $BUILD_DIR/chroot/sys
sudo umount $BUILD_DIR/chroot/run

# Step 16: Finished
echo "Live image build completed successfully!"
echo "The ISO file can be found in $BUILD_DIR"

# Exit script
exit 0
