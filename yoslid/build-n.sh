#!/bin/sh
#=======================================================================
# MyOS - Now linux is easy
# Version: 3.2.1
# (c) Bozhidar Slaveykov https://cloudvision.bg
# MyOS is licensed under GNU General Public License v3.0
#=======================================================================

#=======================================================================
# CONFIGURATION
#=======================================================================
# Target device and distribution information
device="sdc"                                      # Target device to install to
distro_name="MyOS"                                # Distribution name
distro_desc="Now linux is easy"                   # Distribution description
distro_codename="chinchilla"                      # Distribution codename
version="3.2.1"                                   # Distribution version

# Feature flags
telnetd_enabled="true"                            # Enable telnet daemon
hyperv_support="false"                            # Enable Hyper-V support
build_iso="true"                                  # Build ISO image
iso_only="true"                                  # Build ISO only (skip disk operations)
iso_filename="my-os.iso"                          # ISO image filename

# Source URLs
kernel="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.16.19.tar.xz"
busybox="https://busybox.net/downloads/busybox-1.34.1.tar.bz2"

#=======================================================================
# GLOBAL VARIABLES
#=======================================================================
part=1
uuid=""
host=""
arch=""
kernel_release=""
kernel_file=""
initrd_file=""
iso_dir=""
temp_rootfs_dir=""

#=======================================================================
# UTILITY FUNCTIONS
#=======================================================================
# Display usage information
show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help       Display this help message
  -d, --device     Specify target device (default: $device)
  --no-iso         Disable ISO image creation
  --iso-only       Build ISO only (skip disk operations)
  --no-telnetd     Disable telnet daemon
  --hyperv         Enable Hyper-V support

Example:
  $0 --device sdb --no-telnetd
  $0 --iso-only    # Build ISO without disk operations

EOF
  exit 0
}

# Display error message and exit
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

# Display section header
section_header() {
  echo
  echo "** $1"
  echo
}

# Ask user for confirmation
confirm() {
  printf "** $1 (y/n): "
  read answer
  if [ "$answer" != "y" ]; then
    echo "Operation cancelled by user"
    return 1
  fi
  return 0
}

# List available block devices
list_available_devices() {
  echo "** Available block devices:"
  
  # Check if lsblk is available
  if command -v lsblk >/dev/null 2>&1; then
    # Use lsblk to list block devices
    lsblk -d -o NAME,SIZE,MODEL,VENDOR | grep -E 'sd|nvme|mmcblk|loop' || echo "No devices found with lsblk"
  else
    # Fallback to ls if lsblk is not available
    ls -l /dev/sd* /dev/nvme* /dev/mmcblk* /dev/loop* 2>/dev/null || echo "No devices found with ls"
  fi
  
  # Check if any loop devices are available
  if [ -b /dev/loop0 ]; then
    echo "** Loop devices are available (can be used with disk images)"
  fi
}

# Check if a device is valid and available
check_device() {
  local dev="$1"
  
  # Check if device exists
  if [ ! -b "/dev/$dev" ]; then
    echo "Error: Device /dev/$dev does not exist or is not a block device"
    return 1
  fi
  
  # Check if device is mounted
  if mount | grep -q "/dev/$dev"; then
    echo "Error: Device /dev/$dev is currently mounted. Please unmount it first."
    return 1
  fi
  
  # Check if device is a system disk
  if [ "$dev" = "sda" ] || [ "$dev" = "nvme0n1" ] || [ "$dev" = "mmcblk0" ]; then
    echo "Warning: /dev/$dev appears to be a system disk. Are you sure you want to use it?"
    confirm "Continue with /dev/$dev?" || return 1
  fi
  
  return 0
}

# Create and set up a loop device if needed
setup_loop_device() {
  echo "** Setting up a loop device as fallback"
  
  # Create a disk image file
  local image_file="disk.img"
  echo "** Creating disk image file: $image_file (1GB)"
  dd if=/dev/zero of="$image_file" bs=1M count=1024 || error_exit "Failed to create disk image"
  
  # Find an available loop device
  local loop_dev=$(losetup -f)
  if [ -z "$loop_dev" ]; then
    error_exit "No loop device available"
  fi
  
  # Associate the image file with the loop device
  echo "** Associating disk image with $loop_dev"
  losetup "$loop_dev" "$image_file" || error_exit "Failed to set up loop device"
  
  # Extract just the device name without the /dev/ prefix
  device=$(echo "$loop_dev" | sed 's|/dev/||')
  echo "** Using loop device: $loop_dev"
  
  return 0
}

# Select a valid device
select_device() {
  # Skip device selection in ISO-only mode
  if [ "$iso_only" = "true" ]; then
    echo "** ISO-only mode: skipping device selection"
    return 0
  fi
  
  # If device is provided via command line, check it
  if [ -n "$device" ]; then
    if check_device "$device"; then
      echo "** Using device /dev/$device as specified"
      return 0
    else
      echo "** The specified device /dev/$device is not valid"
    fi
  fi
  
  # List available devices
  list_available_devices
  
  # Ask user to select a device
  printf "** Enter device name (e.g., sdb, not /dev/sdb) or 'loop' for a loop device: "
  read selected_device
  
  # Handle loop device request
  if [ "$selected_device" = "loop" ]; then
    setup_loop_device
    return 0
  fi
  
  # Handle empty selection
  if [ -z "$selected_device" ]; then
    echo "** No device selected, trying to set up a loop device as fallback"
    setup_loop_device
    return 0
  fi
  
  # Check if the selected device is valid
  if check_device "$selected_device"; then
    device="$selected_device"
    echo "** Selected device: /dev/$device"
    return 0
  else
    echo "** The selected device is not valid, trying to set up a loop device as fallback"
    setup_loop_device
    return 0
  fi
}

#=======================================================================
# MAIN FUNCTIONS
#=======================================================================
# Check prerequisites and setup
check_prerequisites() {
  section_header "Checking prerequisites"
  
  # Check if running as root
  if [ $(id -u) -ne 0 ]; then
    error_exit "This script must be run as root"
  fi

  # Display welcome message
  clear && printf "\n** $distro_name - creating distribution\n\n"
  
  # Select and validate device (skip in ISO-only mode)
  if [ "$iso_only" != "true" ]; then
    select_device
    
    # Confirm device formatting
    confirm "Are you sure that you want to delete all data from /dev/$device drive?" || exit 1

    # Check if /mnt is mounted and unmount if necessary
    if [ $(mountpoint -qd /mnt) ]; then
      confirm "Can I umount /mnt?" || exit 1
      umount /mnt
    fi
  fi
  
  # Create files directory if it doesn't exist
  [ -d ./files ] || mkdir files
}

# Install BusyBox
install_busybox() {
  section_header "BusyBox installation"
  
  # Check if BusyBox is already compiled
  answer="n"
  if [ -f files/busybox/busybox ]; then
    confirm "Do you want to use a previously compiled BusyBox?" && answer="y"
  fi

  # Compile BusyBox if needed
  if [ "$answer" != "y" ]; then
    # Install required dependencies
    echo "** Installing required dependencies for BusyBox"
    apt update && apt install -y ca-certificates wget build-essential \
      libncurses5 libncurses5-dev bison flex libelf-dev chrpath gawk \
      texinfo libsdl1.2-dev whiptail diffstat cpio libssl-dev bc || \
      error_exit "Failed to install dependencies"

    # Download and extract BusyBox
    echo "** Downloading and extracting BusyBox"
    cd files/ || error_exit "Failed to change to files directory"
    rm -r busybox* > /dev/null 2>&1
    wget "$busybox" -O busybox.tar.bz2 || error_exit "Failed to download BusyBox"
    tar -xf busybox.tar.bz2 || error_exit "Failed to extract BusyBox"
    rm *.tar.bz2
    mv busybox* busybox
    cd busybox || error_exit "Failed to change to busybox directory"
    
    # Configure BusyBox
    echo "** Configuring BusyBox"
    make defconfig || error_exit "Failed to configure BusyBox"
    
    # Modify BusyBox configuration for static build
    echo "** Modifying BusyBox configuration for static build"
    sed 's/^.*CONFIG_STATIC.*$/CONFIG_STATIC=y/' -i .config
    sed 's/^CONFIG_MAN=y/CONFIG_MAN=n/' -i .config
    echo "CONFIG_STATIC_LIBGCC=y" >> .config
    
    # Compile BusyBox
    echo "** Compiling BusyBox (this may take a while)"
    make || error_exit "Failed to compile BusyBox"
    cd ../../ || error_exit "Failed to return to root directory"
  fi
  
  echo "** BusyBox installation completed"
}

# Compile Linux kernel
compile_kernel() {
  section_header "Compilation of the kernel"

  # Determine architecture
  arch=$(uname -m)
  [ "$arch" = 'i686' ] && arch="i386"
  echo "** Detected architecture: $arch"

  # Check if kernel is already compiled
  answer="n"
  if [ -f files/linux/arch/$arch/boot/bzImage ]; then
    confirm "Do you want to use a previously compiled kernel?" && answer="y"
  fi

  # Compile kernel if needed
  if [ "$answer" != "y" ]; then
    echo "** Downloading and extracting kernel"
    cd files || error_exit "Failed to change to files directory"
    rm -r linux* > /dev/null 2>&1
    wget "$kernel" || error_exit "Failed to download kernel"
    tar -xf *.tar.xz || error_exit "Failed to extract kernel"
    rm linux-*.tar.xz
    mv linux* linux
    cd linux || error_exit "Failed to change to linux directory"

    # Add Hyper-V support if enabled
    if [ "$hyperv_support" = "true" ]; then
      echo "** Adding Hyper-V support to kernel configuration"
      cat <<EOF >> arch/x86/configs/x86_64_defconfig
CONFIG_HYPERVISOR_GUEST=y
CONFIG_PARAVIRT=y
CONFIG_CONNECTOR=y
CONFIG_HYPERV=y
CONFIG_HYPERV_NET=y
EOF
    fi

    # Configure and build kernel
    echo "** Configuring kernel"
    make defconfig || error_exit "Failed to configure kernel"
    echo "** Building kernel (this will take a while)"
    make || error_exit "Failed to compile kernel"
    cd ../../ || error_exit "Failed to return to root directory"
  fi

  # Set kernel and initrd filenames
  echo "** Setting kernel and initrd filenames"
  kernel_release=$(cat files/linux/include/config/kernel.release) || error_exit "Failed to get kernel release"
  kernel_file=vmlinuz-$kernel_release-$arch
  initrd_file=initrd.img-$kernel_release-$arch
  echo "** Kernel: $kernel_file"
  echo "** Initrd: $initrd_file"

  # Copy kernel to boot directory (skip in ISO-only mode)
  if [ "$iso_only" != "true" ]; then
    echo "** Copying kernel to boot directory"
    cp files/linux/arch/$arch/boot/bzImage /mnt/boot/$kernel_file || error_exit "Failed to copy kernel"
  fi
}


# Create root filesystem structure
create_rootfs() {
  section_header "Creating root filesystem structure"

  # Create rootfs directory and change to it
  echo "** Creating rootfs directory"
  
  # In ISO-only mode, create a temporary directory for rootfs
  if [ "$iso_only" = "true" ]; then
    temp_rootfs_dir=$(mktemp -d) || error_exit "Failed to create temporary directory"
    mkdir -p $temp_rootfs_dir/rootfs || error_exit "Failed to create rootfs directory"
    cd $temp_rootfs_dir/rootfs || error_exit "Failed to change to rootfs directory"
  else
    mkdir rootfs || error_exit "Failed to create rootfs directory"
    cd rootfs || error_exit "Failed to change to rootfs directory"
  fi

  # Create directory structure
  echo "** Creating directory structure"
  mkdir -p bin dev lib lib64 run mnt/root proc sbin sys 
  mkdir -p usr/bin usr/sbin usr/share/udhcpc usr/local/bin
  mkdir -p tmp home var/log var/run var/www/html
  mkdir -p var/spool/cron/crontabs 
  mkdir -p etc/init.d etc/rc.d
  mkdir -p etc/network/if-down.d etc/network/if-post-down.d etc/network/if-pre-up.d etc/network/if-up.d
  mkdir -p etc/cron/daily etc/cron/hourly etc/cron/monthly etc/cron/weekly

  # Install BusyBox and set up directories with proper permissions
  echo "** Installing BusyBox"
  BUSSYBOX_PATH=$(find ../files/busybox/ -name busybox)
  cp ../files/busybox/busybox bin || error_exit "Failed to copy BusyBox"
  install -d -m 0750 root
  install -d -m 1777 tmp

  # Copy required DNS libraries
  echo "** Copying system libraries"
  for i in $(find /lib/ | grep 'ld-2\|ld-lin\|libc.so\|libnss_dns\|libresolv'); do
    cp ${i} lib || error_exit "Failed to copy library: $i"
  done
}

# Configure system files
configure_system() {
  section_header "System configuration"

  # Create device nodes
  echo "** Creating device nodes"
  mknod dev/console c 5 1
  mknod dev/tty c 5 0

  # Generate hostname from distribution name (lowercase, first word) if not already set
  if [ -z "$host" ]; then
    host=$(printf $(printf $distro_name | tr A-Z a-z) | cut -d" " -f 1)
    echo "** Generated hostname: $host"
  fi

  # Basic system configuration files
  echo "** Creating basic system configuration files"
  echo "$host" > etc/hostname
  cat > etc/passwd << EOF
root:x:0:0:root:/root:/bin/sh
service:x:1:1:service:/var/www/html:/usr/sbin/nologin
EOF

  echo "root:mKhhqXFCdhNiA:17743::::::" > etc/shadow

  cat > etc/group << EOF
root:x:0:root
service:x:1:service
EOF

  echo "/bin/sh" > etc/shells
  echo "127.0.0.1	 localhost $host" > etc/hosts

  # Create default web page
  echo "** Creating default web page"
  cat > var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <title>$distro_name httpd default page: It works</title>
  <style>
    body {
      background-color: #004c75;
    }
    h1, p {
      margin-top: 60px;
      color: #d4d4d4;
      text-align: center;
      font-family: Arial;
    }
  </style>
</head>
<body>
  <h1>It works!</h1>
  <hr>
  <p><b>$distro_name httpd</b> default page<br>ver. $version</p>
</body>
</html>
EOF

  # Create fstab (skip UUID in ISO-only mode)
  echo "** Creating fstab"
  if [ "$iso_only" = "true" ]; then
    echo "# Placeholder fstab for ISO-only mode" > etc/fstab
  else
    echo "UUID=$uuid  /  ext4  defaults,errors=remount-ro  0  1" > etc/fstab
  fi

  # Configure shell environment
  echo "** Configuring shell environment"
  cat > etc/profile << EOF
# Display system information on login
uname -snrvm
echo

# Set PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin

# Set prompt (green for regular users, plain for root)
export PS1="\\e[0;32m\\u@\\h:\\w\\\$ \\e[m"
[ \$(id -u) -eq 0 ] && export PS1="\\u@\\h:\\w# "

# Useful aliases
alias vim=vi
alias l.='ls -d .*'
alias ll='ls -Al'
alias su='su -l'
alias logout='clear;exit'
alias exit='clear;exit'
alias locate=which
alias whereis=which
alias useradd=adduser
EOF

  # Create login banner
  echo "** Creating login banner"
  printf "\n\e[96m${*}$distro_name\e[0m${*} Linux \e[97m${*}$version\e[0m${*} - $distro_desc\n\n" | tee -a etc/issue usr/share/infoban >/dev/null
  cat >> etc/issue << EOF
 * Default root password:        Yosild
 * Networking:                   ifupdown
 * Init scripts installer:       add-rc.d
 * To disable this message:      disban

EOF

  # Create disban script to disable the banner
  echo "cp /usr/share/infoban /etc/issue" > sbin/disban

  # Create legal notice (MOTD)
  echo "** Creating MOTD"
  cat > etc/motd << EOF

The programs included with the $distro_name Linux system are free software.
$distro_name Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.

EOF

  # Create os-release file
  echo "** Creating os-release file"
  cat > etc/os-release << EOF
PRETTY_NAME="$distro_name - $distro_desc ($distro_codename)"
NAME="$distro_name"
VERSION_ID="$version"
VERSION="$version"
VERSION_CODENAME="$distro_codename"
ID="$distro_name"
HOME_URL="https://github.com/jaromaz/yosild"
SUPPORT_URL="https://jm.iq.pl/yosild"
BUG_REPORT_URL="https://github.com/jaromaz/yosild/issues"
EOF

  # Configure inittab
  echo "** Configuring inittab"
  cat > etc/inittab << EOF
# TTY configuration
tty1::respawn:/sbin/getty 38400 tty1
tty2::askfirst:/sbin/getty 38400 tty2
tty3::askfirst:/sbin/getty 38400 tty3
tty4::askfirst:/sbin/getty 38400 tty4

# System initialization
::sysinit:/sbin/swapon -a
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/etc/init.d/rcS

# Special keys
::ctrlaltdel:/sbin/reboot

# Shutdown sequence
::shutdown:/bin/echo SHUTTING DOWN
::shutdown:/sbin/swapoff -a
::shutdown:/etc/init.d/rcK
::shutdown:/bin/umount -a -r
EOF

  # Configure network interfaces
  echo "** Configuring network interfaces"
  cat > etc/network/interfaces << EOF
# Loopback interface
auto lo
iface lo inet loopback

# Primary network interface
auto eth0
iface eth0 inet dhcp
EOF
}

# Create init script
create_init_script() {
  section_header "Creating init script"
  
  echo "** Creating init script"
  
  # In ISO-only mode, use a placeholder UUID
  local init_uuid="$uuid"
  if [ "$iso_only" = "true" ]; then
    init_uuid="00000000-0000-0000-0000-000000000000"
  fi
  
  cat > init << EOF
#!/bin/busybox sh

# Install busybox symlinks and set PATH
/bin/busybox --install -s
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount virtual filesystems
mountpoint -q proc || mount -t proc proc proc
mountpoint -q sys || mount -t sysfs sys sys

# Create /dev/null device node
mknod /dev/null c 1 3

# Set up device filesystem if not already mounted
if ! mountpoint -q dev; then
  mount -t tmpfs -o size=64k,mode=0755 tmpfs dev
  mount -t tmpfs -o mode=1777 tmpfs tmp
  mkdir -p dev/pts
  mdev -s
  chown -R service:service /var/www
fi

# Reduce kernel messages
echo 0 > /proc/sys/kernel/printk
sleep 1

# Mount root filesystem
mount -t ext4 UUID=$init_uuid /mnt/root/
mount -t tmpfs run /run -o mode=0755,nosuid,nodev

# Copy files to root filesystem if it's empty
if [ ! -d /mnt/root/bin ]; then
  for i in bin etc lib root sbin usr home var; do
    cp -r -p /\$i /mnt/root
  done
  mkdir /mnt/root/mnt
fi

# Bind mount virtual filesystems
for i in run tmp dev proc sys; do
  [ -d /mnt/root/\$i ] || mkdir /mnt/root/\$i
  mount -o bind /\$i /mnt/root/\$i
done

# Mount devpts
mount -t devpts none /mnt/root/dev/pts

# Clean up and chroot
rm -r /bin /etc /sbin /usr
exec /mnt/root/bin/busybox chroot /mnt/root /sbin/init
EOF
}

# Create utility scripts
create_utility_scripts() {
  section_header "Creating utility scripts"
  
  # Create nologin script
  echo "** Creating nologin script"
  cat > usr/sbin/nologin << EOF
#!/bin/sh
echo 'This account is currently not available.'
sleep 3
exit 1
EOF

  # Create halt script
  echo "** Creating halt script"
  cat > sbin/halt << EOF
#!/bin/sh
if [ \$1 ] && [ \$1 = '-p' ]; then
    /bin/busybox poweroff
    return 0
fi
/bin/busybox halt
EOF

  # Create mini man page script
  echo "** Creating man page script"
  cat > sbin/man << EOF
#!/bin/sh
# Simple man page implementation using busybox help
if [ -z "\$(busybox \$1 --help 2>&1 | head -1 | grep 'applet not found')" ]; then
  clear
  head="\$(echo \$1 | tr 'a-z' 'A-Z')(1)\\t\\t\\tManual page\\n"
  body="\$(busybox \$1 --help 2>&1 | tail -n +2)\\n\\n"
  printf "\$head\$body" | more
  exit 0
fi
echo "No manual entry for \$1"
EOF

  # Create init scripts
  echo "** Creating init scripts"
  cat > etc/init.d/rcS << EOF
#!/bin/sh
. /etc/init.d/init-functions
rc
EOF

  # Link rcK to rcS
  ln -s /etc/init.d/rcS etc/init.d/rcK
}

# Configure cron
configure_cron() {
  section_header "Configuring cron"
  
  # Configure default crontabs
  echo "** Creating default crontabs"
  cat > var/spool/cron/crontabs/root << EOF
# Run cron jobs at specific times
15  * * * *   cd / && run-parts /etc/cron/hourly
23  6 * * *   cd / && run-parts /etc/cron/daily
47  6 * * 0   cd / && run-parts /etc/cron/weekly
33  5 1 * *   cd / && run-parts /etc/cron/monthly
EOF

  # Create logrotate script
  echo "** Creating logrotate script"
  cat > usr/sbin/logrotate << EOF
#!/bin/sh
# Simple log rotation script
maxsize=512
dir=/var/log

# Find logs that need rotation
for log in \$(ls -1 \${dir} | grep -Ev '\.gz$'); do
  size=\$(du "\$dir/\$log" | tr -s '\t' ' ' | cut -d' ' -f1)
  if [ "\$size" -gt "\$maxsize" ] ; then
    tsp=\$(date +%s)
    mv "\$dir/\$log" "\$dir/\$log.\$tsp"
    touch "\$dir/\$log"
    gzip "\$dir/\$log.\$tsp"
  fi
done
EOF

  # Add logrotate to daily cron jobs
  ln -s ../../../usr/sbin/logrotate etc/cron/daily/logrotate
}

# Create init scripts installer
create_init_scripts_installer() {
  section_header "Creating init scripts installer"
  
  echo "** Creating add-rc.d script"
  cat > usr/bin/add-rc.d << EOF
#!/bin/sh
# Tool to add init scripts to the system
if [ -f /etc/init.d/\$1 ] && [ "\$2" -gt 0 ] ; then
  ln -s /etc/init.d/\$1 /etc/rc.d/\$2\$1
  echo "added \$1 to init."
else
  echo "
  ** $distro_name add-rc.d ussage:

  add-rc.d [init.d script name] [order number]

  examples:
  add-rc.d httpd 40
  add-rc.d ftpd 40
  add-rc.d telnetd 50
  "
fi
EOF
}

# Create startup scripts
create_startup_scripts() {
  section_header "Creating startup scripts"
  
  # Define startup services
  echo "** Creating startup service scripts"
  initdata="
networking|network|30|/sbin/ifup|-a|/sbin/ifdown
telnetd|telnet daemon|80|/usr/sbin/telnetd|-p 23
cron|cron daemon|20|/usr/sbin/crond
syslogd|syslog|10|/sbin/syslogd
httpd|http server||/usr/sbin/httpd|-vvv -f -u service -h /var/www/html||httpd.log
ftpd|ftp daemon||/usr/bin/tcpsvd|-vE 0.0.0.0 21 ftpd -S -a service -w /var/www/html"

  # Save original IFS
  OIFS=$IFS

  # Process each service
  IFS='
'
  for i in $initdata; do
    # Split fields by pipe
    IFS='|'
    set -- $i
    
    echo "** Creating init script for $1"
    
    # Create init script for this service
    cat > etc/init.d/$1 << EOF
#!/bin/sh
NAME="$1"
DESC="$2"
DAEMON="$4"
PARAMS="$5"
STOP="$6"
LOG="$7"
PIDFILE=/var/run/$1.pid

. /etc/init.d/init-functions
init \$@
EOF
    
    # Set permissions
    chmod 744 etc/init.d/$1
    
    # Skip telnetd if disabled
    [ $1 = 'telnetd' ] && [ "$telnetd_enabled" = "false" ] && continue;
    
    # Create symlink if order number is provided
    [ "$3" ] && ln -s ../init.d/$1 etc/rc.d/$3$1.sh
  done

  # Restore original IFS
  IFS=$OIFS
}

# Install compressed scripts
install_compressed_scripts() {
  section_header "Installing compressed scripts"

  # BusyBox DHCP client script (compressed and base64 encoded)
  echo "** Installing DHCP client script"
  cat << EOF | base64 -d | gzip -d > usr/share/udhcpc/default.script
H4sICOcUYlsAA2RoY3Auc2gAzVZNT9tAED17f8VgLEhAxEmP0ESilF7aggSol4ZGm/U4XmHvml07
gZb+944/kloxH6HtoRvFSXZn3sy8N2Nne8ufSuXbiG1DHkQiFWCFkWkGGMgMA5jew5VM4ELeoIG3
xVeeVb9sT5vZiH2Fg+/gegMXrmFnB1BEGtxTY7Q5BBvpPCYMBMHjmNBCo5M6jlta38kMBuzi9PL8
05fJyfnZh6HrYyZ8g1bH857QKnSLEIpCTI3mgeA2q0O9uzg/fn9yfHk1dFdH0LBa+tl8qnDpdHZ6
9fn48uPQpa2E2xtYHhMBBrPcKOiDDMFonYG0kOhcFTxoBRzIbqHNDYQyRntvM0xYYTeRdqJC2+nC
D+bMDKZwcIuw+80PcO4XBr29cYcMxg82mRYfSqTjB6EDPu5Cb28X/NRo4ZehLPvJIj7HCckykemw
zygZKuQOSqFkCtdHkEWoGEDTbsBCyahsrLSQijkBFvTJWZc5DoFsQSNXWIE8vsqgXiMAHOAtDBrB
n1/kwIPAQBjnNgLiATxJPJqQC9zEOZbqBixma66Qp096Y2xfhvZtyWJYMdNE7vfK15MIRK/jlJej
I8YcgwoXD1OSLOi2fP6UvSVrdFkvPNY0QrSR+l7Vtqvub6E9S8TTBBB2AxW8elJaSMRB1VD1eBmd
E0QxXnV1zuvb7W+JW1+LiCa0oLNMjriM6R3yPM7gzagcS5XHMWUV6I0xl+twY49Aq5c7cqO2Xa6q
rnZRs8Wyf9f75n8rt5ygao6cBDMjBd3iih1tQNJtC+p+2izZf9Uvq06pJq8idS45MQlVluB1OtW3
/f1ue+LX16tUbYcmPSnympSPJdLUd0PuS5lqCcqnNU3xCLzGM5gO6tkOdMKlaj7aLXIjIqhPYNTy
/C1koGylolMHogqlmkGx78nVruIJWjRz0pxqbgPW+dJdFy0XrPzL0Ge/AHxZ2lW5CAAA
EOF

  # Startup scripts functions (compressed and base64 encoded)
  echo "** Installing init functions script"
  cat << EOF | base64 -d | gzip -d > etc/init.d/init-functions
H4sICMdmNFwAA2luaXQtZnVuY3Rpb25zAHVSXW/aMBR99684eBYiSMR0j0UFoZVNaOVjDXtCfcgS
A9aiJLJNhVT63+fYWZIyzU/2/Tj3nHP9qcd/yZzrEyEylwaDAG/ECG0wOoA9zherzRrXK8TFJsck
ibUAZXcUMieANrEygb0AIjkVoFEVkPnRti6iL2EYUpcE5AF7sKfNN7xgAnMSeZ1AM4Vt58/zVYTP
0yl/jRXPiiN3Hf26VGRa/LerP+WpeOX5OcuahoNsqbEeprZ4+fh1+bRw4cnEKSjKjwKKsvxXgKcf
7TbbW/4+WLMgNzT3zsV6qO3s9/FbWoJskMSmSQRd8qRD3DFUwrl8VSIr4tRzpWxMHfXuyxa1XcOu
KLaerxZw+9WJkqXBWcdHcQ82xptHr8Cu9ah3r1kJc1Y57ojQcULqF5uRd0JU4j+Ks2WUgguTcJWE
qde4r4AfHkBdvJobpjb9neKl492hULhYVtaNTGOkWhQeWI/Totl1m2CXVnZa5OIjUWtbBSor0LZn
Nhv+hdujV22EMkk906TI7Xc9e5z6c8v6c1dnGOpT0PAYNDfAqLjECMv1Dj9+LnfYRbttJ62F6azE
nxBMNs8W1e2rHhd0ypm8Ragr3T6cep0JUVrhSSZiRRof7Ib+AOWFyVTYAwAA
EOF
}

# Set file permissions
set_permissions() {
  section_header "Setting file permissions"

  # Create empty files
  echo "** Creating empty files"
  touch proc/mounts var/log/wtmp var/log/lastlog

  # Set permissions for security-sensitive files
  echo "** Setting permissions for security-sensitive files"
  chmod 640 etc/shadow etc/inittab
  chmod 664 var/log/lastlog var/log/wtmp
  chmod 4755 bin/busybox
  chmod 600 var/spool/cron/crontabs/root

  # Set permissions for executable scripts
  echo "** Setting permissions for executable scripts"
  chmod 755 usr/sbin/nologin sbin/disban init sbin/man etc/init.d/rcS \
            usr/sbin/logrotate usr/bin/add-rc.d sbin/halt \
            usr/share/udhcpc/default.script

  # Set permissions for configuration files
  echo "** Setting permissions for configuration files"
  chmod 644 etc/passwd etc/group etc/hostname etc/shells etc/hosts etc/fstab \
            etc/issue etc/motd etc/network/interfaces etc/profile
}

# Build initramfs
build_initramfs() {
  section_header "Building initramfs"

  # Create initramfs image
  echo "** Creating initramfs image"
  find . | cpio -H newc -o 2> /dev/null | gzip > ../initramfs.gz || \
    error_exit "Failed to create initramfs"
  
  # In ISO-only mode, keep the initramfs in the temp directory
  if [ "$iso_only" != "true" ]; then
    # Copy initramfs to boot directory
    cp ../initramfs.gz /mnt/boot/$initrd_file || error_exit "Failed to copy initramfs to boot directory"
    # Clean up
    rm ../initramfs.gz
    cd .. || error_exit "Failed to return to root directory"
    rm -r rootfs || error_exit "Failed to remove rootfs directory"
    umount /mnt || error_exit "Failed to unmount /mnt"
  else
    # In ISO-only mode, just change directory
    cd .. || error_exit "Failed to return to parent directory"
    # Keep the initramfs for ISO creation
    mv initramfs.gz $initrd_file || error_exit "Failed to rename initramfs"
  fi
}

# Build ISO image
build_iso_image() {
  # Skip if ISO build is disabled
  if [ "$build_iso" != "true" ]; then
    echo "** ISO image creation is disabled, skipping"
    return 0
  fi
  
  section_header "Building ISO image"
  
  # Install required packages
  echo "** Installing required packages for ISO creation"
  apt update && apt install -y xorriso grub-common grub-pc-bin mtools \
    libc6 libdevmapper1.02.1 liblzma5 dosfstools uuid-runtime || \
    error_exit "Failed to install ISO creation dependencies"
  
  # Create temporary directory structure
  echo "** Creating temporary directory structure"
  iso_dir=$(mktemp -d) || error_exit "Failed to create temporary directory"
  mkdir -p $iso_dir/boot/grub || error_exit "Failed to create ISO directory structure"
  
  # Copy kernel and initramfs to ISO directory
  echo "** Copying kernel and initramfs to ISO directory"
  
  # In ISO-only mode, use the files from the temp directory
  if [ "$iso_only" = "true" ]; then
    cp files/linux/arch/$arch/boot/bzImage $iso_dir/boot/$kernel_file || \
      error_exit "Failed to copy kernel to ISO directory"
    cp $initrd_file $iso_dir/boot/$initrd_file || \
      error_exit "Failed to copy initramfs to ISO directory"
  else
    cp /mnt/boot/$kernel_file $iso_dir/boot/ || error_exit "Failed to copy kernel to ISO directory"
    cp /mnt/boot/$initrd_file $iso_dir/boot/ || error_exit "Failed to copy initramfs to ISO directory"
  fi
  
  # Create GRUB configuration for ISO
  echo "** Creating GRUB configuration for ISO"
  cat > $iso_dir/boot/grub/grub.cfg << EOF || error_exit "Failed to create GRUB configuration for ISO"
set timeout=5
set default=0

menuentry "$distro_name - $distro_desc (Live)" {
  linux /boot/$kernel_file quiet
  initrd /boot/$initrd_file
  boot
}
EOF
  
  # Create the ISO image
  echo "** Creating ISO image: $iso_filename"
  grub-mkrescue -o $iso_filename $iso_dir || error_exit "Failed to create ISO image"
  
  # Clean up temporary files
  echo "** Cleaning up temporary files"
  rm -rf $iso_dir || error_exit "Failed to clean up temporary directory"
  
  # In ISO-only mode, clean up the temp rootfs directory
  if [ "$iso_only" = "true" ]; then
    rm -rf $temp_rootfs_dir || echo "Warning: Failed to remove temporary rootfs directory"
    rm $initrd_file || echo "Warning: Failed to remove temporary initramfs file"
  fi
  
  echo "** ISO image created: $iso_filename"
}

# Process command line arguments
process_args() {
  echo "** Processing command line arguments"
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        show_usage
        ;;
      -d|--device)
        device="$2"
        shift
        ;;
      --no-iso)
        build_iso="false"
        ;;
      --iso-only)
        iso_only="true"
        build_iso="true"
        echo "** ISO-only mode enabled (skipping disk operations)"
        ;;
      --no-telnetd)
        telnetd_enabled="false"
        ;;
      --hyperv)
        hyperv_support="true"
        ;;
      *)
        echo "Unknown option: $1"
        show_usage
        ;;
    esac
    shift
  done
}

# Main function
main() {
  # Process command line arguments
  process_args "$@"
  
  # Run all functions in sequence
  check_prerequisites
  install_busybox
  
  
  compile_kernel

  create_rootfs
  configure_system
  create_init_script
  create_utility_scripts
  configure_cron
  create_init_scripts_installer
  create_startup_scripts
  install_compressed_scripts
  set_permissions
  build_initramfs
  
 build_iso_image
  
  section_header "$distro_name ISO image created successfully"
}

# Run main function with all arguments
main "$@"
