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
iso_filename="my-os.iso"                          # ISO image filename

# Source URLs
kernel="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.16.19.tar.xz"
coreutils="https://ftp.gnu.org/gnu/coreutils/coreutils-9.4.tar.xz"
findutils="https://ftp.gnu.org/gnu/findutils/findutils-4.9.0.tar.xz"
grep="https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz"
sed="https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz"
gawk="https://ftp.gnu.org/gnu/gawk/gawk-5.2.2.tar.xz"
bash="https://ftp.gnu.org/gnu/bash/bash-5.2.21.tar.gz"
#=======================================================================

#=======================================================================
# INITIAL CHECKS AND SETUP
#=======================================================================
# Check if running as root
if [ $(id -u) -ne 0 ]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Display welcome message and confirm device formatting
clear && printf "\n** $distro_name - creating distribution\n\n"
printf "** Are you sure that you want to delete all data from /dev/$device drive? (y/n): "
read answer
[ "$answer" != "y" ] && exit 1

# Check if /mnt is mounted and unmount if necessary
if [ $(mountpoint -qd /mnt) ]; then
  printf "** Can I umount /mnt? (y/n): "
  read answer
  [ "$answer" != "y" ] && exit 1
  umount /mnt
fi

#=======================================================================
# GNU COREUTILS INSTALLATION
#=======================================================================
# Create files directory if it doesn't exist
[ -d ./files ] || mkdir files

# Check if GNU utilities are already compiled
answer="n"
if [ -f files/coreutils/src/ls ] && [ -f files/bash/bash ]; then
  printf "** Do you want to use previously compiled GNU utilities? (y/n): "
  read answer
fi

# Compile GNU utilities if needed
if [ "$answer" != "y" ]; then
  echo "** GNU utilities installation"

  # Install required dependencies
  apt update && apt install -y ca-certificates wget build-essential \
    libncurses5 libncurses5-dev bison flex libelf-dev chrpath gawk \
    texinfo libsdl1.2-dev whiptail diffstat cpio libssl-dev bc \
    gettext autoconf automake libtool

  # Create GNU utilities directory
  cd files/
  mkdir -p gnu_utils

  # Download and compile coreutils
  echo "** Compiling GNU coreutils"
  rm -rf coreutils* > /dev/null 2>&1
  wget "$coreutils" -O coreutils.tar.xz
  tar -xf coreutils.tar.xz
  rm coreutils.tar.xz
  mv coreutils* coreutils
  cd coreutils
  
  # Configure coreutils for static build
  ./configure --prefix=/usr --enable-static --disable-shared --disable-nls
  
  # Compile coreutils
  make
  cd ..

  # Download and compile findutils
  echo "** Compiling GNU findutils"
  rm -rf findutils* > /dev/null 2>&1
  wget "$findutils" -O findutils.tar.xz
  tar -xf findutils.tar.xz
  rm findutils.tar.xz
  mv findutils* findutils
  cd findutils
  
  # Configure findutils for static build
  ./configure --prefix=/usr --enable-static --disable-shared --disable-nls
  
  # Compile findutils
  make
  cd ..

  # Download and compile grep
  echo "** Compiling GNU grep"
  rm -rf grep* > /dev/null 2>&1
  wget "$grep" -O grep.tar.xz
  tar -xf grep.tar.xz
  rm grep.tar.xz
  mv grep* grep
  cd grep
  
  # Configure grep for static build
  ./configure --prefix=/usr --enable-static --disable-shared --disable-nls
  
  # Compile grep
  make
  cd ..

  # Download and compile sed
  echo "** Compiling GNU sed"
  rm -rf sed* > /dev/null 2>&1
  wget "$sed" -O sed.tar.xz
  tar -xf sed.tar.xz
  rm sed.tar.xz
  mv sed* sed
  cd sed
  
  # Configure sed for static build
  ./configure --prefix=/usr --enable-static --disable-shared --disable-nls
  
  # Compile sed
  make
  cd ..

  # Download and compile gawk
  echo "** Compiling GNU awk"
  rm -rf gawk* > /dev/null 2>&1
  wget "$gawk" -O gawk.tar.xz
  tar -xf gawk.tar.xz
  rm gawk.tar.xz
  mv gawk* gawk
  cd gawk
  
  # Configure gawk for static build
  ./configure --prefix=/usr --enable-static --disable-shared --disable-nls
  
  # Compile gawk
  make
  cd ..

  # Download and compile bash
  echo "** Compiling GNU bash"
  rm -rf bash* > /dev/null 2>&1
  wget "$bash" -O bash.tar.gz
  tar -xf bash.tar.gz
  rm bash.tar.gz
  mv bash* bash
  cd bash
  
  # Configure bash for static build
  ./configure --prefix=/usr --enable-static-link --without-bash-malloc
  
  # Compile bash
  make
  cd ../../
fi


#=======================================================================
# DISK PARTITIONING AND FORMATTING
#=======================================================================
echo "** Partitioning /dev/$device" && sleep 2
part=1
lba=2048

# Clear any existing partition table
wipefs -af /dev/$device

# Create a new partition
echo "** Preparation of the system partition"
printf "n\np\n${part}\n2048\n\nw\n" | \
  fdisk /dev/$device > /dev/null 2>&1

# Format the partition with ext4
echo y | mkfs.ext4 /dev/${device}${part}

# Get the UUID of the new partition
uuid=$(blkid /dev/${device}${part} -sUUID -ovalue)

# Mount the new partition and create boot directory
mount /dev/${device}${part} /mnt
rm -rf /mnt/boot
mkdir /mnt/boot

# Generate hostname from distribution name (lowercase, first word)
host=$(printf $(printf $distro_name | tr A-Z a-z) | cut -d" " -f 1)

#=======================================================================
# KERNEL COMPILATION
#=======================================================================
echo "** Compilation of the kernel"

# Determine architecture
arch=$(uname -m)
[ "$arch" = 'i686' ] && arch="i386"

# Check if kernel is already compiled
answer="n"
if [ -f files/linux/arch/$arch/boot/bzImage ]; then
  printf "** Do you want to use a previously compiled kernel? (y/n): "
  read answer
fi

# Compile kernel if needed
if [ "$answer" != "y" ]; then
  cd files
  rm -r linux* > /dev/null 2>&1
  wget "$kernel"
  tar -xf *.tar.xz
  rm linux-*.tar.xz
  mv linux* linux
  cd linux

  # Add Hyper-V support if enabled
  if [ "$hyperv_support" = "true" ]; then
    cat <<EOF >> arch/x86/configs/x86_64_defconfig
CONFIG_HYPERVISOR_GUEST=y
CONFIG_PARAVIRT=y
CONFIG_CONNECTOR=y
CONFIG_HYPERV=y
CONFIG_HYPERV_NET=y
EOF
  fi

  # Configure and build kernel
  make defconfig
  make
  cd ../../
fi

# Set kernel and initrd filenames
kernel_release=$(cat files/linux/include/config/kernel.release)
kernel_file=vmlinuz-$kernel_release-$arch
initrd_file=initrd.img-$kernel_release-$arch

# Copy kernel to boot directory
cp files/linux/arch/$arch/boot/bzImage /mnt/boot/$kernel_file

#=======================================================================
# GRUB BOOTLOADER INSTALLATION
#=======================================================================
echo "** Installation of GRUB"
grub-install --root-directory=/mnt /dev/$device

# Create GRUB configuration
cat > /mnt/boot/grub/grub.cfg << EOF
timeout=3
menuentry '$distro_name - $distro_desc' {
  linux /boot/$kernel_file root=UUID=$uuid rootfstype=ext4 rootwait quiet
  initrd /boot/$initrd_file
  boot
  echo Loading Linux
}
EOF

#=======================================================================
# ROOTFS CREATION
#=======================================================================
echo "** Creating root filesystem structure"

# Create rootfs directory and change to it
mkdir rootfs
cd rootfs

# Create directory structure
mkdir -p bin dev lib lib64 run mnt/root proc sbin sys 
mkdir -p usr/bin usr/sbin usr/share/udhcpc usr/local/bin
mkdir -p tmp home var/log var/run var/www/html
mkdir -p var/spool/cron/crontabs 
mkdir -p etc/init.d etc/rc.d
mkdir -p etc/network/if-down.d etc/network/if-post-down.d etc/network/if-pre-up.d etc/network/if-up.d
mkdir -p etc/cron/daily etc/cron/hourly etc/cron/monthly etc/cron/weekly

# Install GNU utilities and set up directories with proper permissions
echo "** Installing GNU utilities"
# Copy coreutils binaries
for util in ../files/coreutils/src/*; do
  if [ -x "$util" ] && [ -f "$util" ]; then
    cp "$util" bin/
  fi
done

# Copy findutils binaries
cp ../files/findutils/find/find bin/
cp ../files/findutils/xargs/xargs bin/
cp ../files/findutils/locate/locate bin/

# Copy grep
cp ../files/grep/src/grep bin/

# Copy sed
cp ../files/sed/sed/sed bin/

# Copy gawk
cp ../files/gawk/gawk bin/
ln -sf gawk bin/awk

# Copy bash
cp ../files/bash/bash bin/
ln -sf bash bin/sh

# Add essential utilities for initramfs
echo "** Adding essential utilities for initramfs"
# Copy switch_root from host system
cp /sbin/switch_root sbin/
# Copy mount utilities
cp /bin/mount bin/
cp /bin/umount bin/
# Copy modprobe for kernel module loading
cp /sbin/modprobe sbin/
# Copy insmod for direct module loading
cp /sbin/insmod sbin/

install -d -m 0750 root
install -d -m 1777 tmp

# Copy required system libraries
echo "** Copying system libraries"
# Copy basic C libraries
for i in $(find /lib/ | grep 'ld-2\|ld-lin\|libc.so\|libnss_dns\|libresolv'); do
    cp ${i} lib
done

# Copy additional libraries needed for system utilities
for lib in libblkid.so libmount.so libselinux.so libpcre.so libpthread.so libdl.so libcap.so; do
    for path in $(find /lib/ /usr/lib/ -name "${lib}*" 2>/dev/null); do
        cp ${path} lib/
    done
done

# Copy kernel modules if they exist
if [ -d /lib/modules/$(uname -r) ]; then
    mkdir -p lib/modules/
    cp -r /lib/modules/$(uname -r) lib/modules/
fi

#=======================================================================
# SYSTEM CONFIGURATION
#=======================================================================
echo "** System configuration"

# Create device nodes
mknod dev/console c 5 1
mknod dev/tty c 5 0

# Basic system configuration files
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

# Create fstab
echo "UUID=$uuid  /  ext4  defaults,errors=remount-ro  0  1" > etc/fstab

# Configure shell environment
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
cat > etc/motd << EOF

The programs included with the $distro_name Linux system are free software.
$distro_name Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.

EOF

# Create os-release file
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
cat > etc/network/interfaces << EOF
# Loopback interface
auto lo
iface lo inet loopback

# Primary network interface
auto eth0
iface eth0 inet dhcp
EOF

#=======================================================================
# INIT SCRIPT
#=======================================================================
# Create a very simple init script
cat > init << EOF
#!/bin/sh

# Set PATH
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev || mount -t tmpfs none /dev

# Create essential device nodes if devtmpfs is not available
if [ ! -e /dev/console ]; then
  mknod /dev/console c 5 1
  mknod /dev/null c 1 3
  mknod /dev/tty c 5 0
  mkdir -p /dev/pts
  mount -t devpts none /dev/pts
fi

# Wait for devices to settle
sleep 2

# Try to mount root filesystem by UUID
echo "Mounting root filesystem..."
mkdir -p /mnt/root
mount -t ext4 /dev/disk/by-uuid/$uuid /mnt/root || {
  # If UUID mount fails, try to find the root device
  echo "UUID mount failed, trying to find root device..."
  for dev in sda1 sdb1 sdc1 vda1 hda1; do
    if mount -t ext4 /dev/\$dev /mnt/root 2>/dev/null; then
      echo "Mounted /dev/\$dev as root"
      break
    fi
  done
}

# Check if root was mounted
if [ ! -d /mnt/root/bin ]; then
  echo "Failed to mount root filesystem!"
  exec sh
fi

# Prepare for switch_root
mount --move /proc /mnt/root/proc
mount --move /sys /mnt/root/sys
mount --move /dev /mnt/root/dev

# Switch to the new root
echo "Switching to new root..."
exec switch_root /mnt/root /sbin/init || exec sh
EOF

#=======================================================================
# UTILITY SCRIPTS
#=======================================================================
# Create nologin script
cat > usr/sbin/nologin << EOF
#!/bin/sh
echo 'This account is currently not available.'
sleep 3
exit 1
EOF

# Create halt script
cat > sbin/halt << EOF
#!/bin/sh
if [ \$1 ] && [ \$1 = '-p' ]; then
    poweroff
    return 0
fi
halt
EOF

# Create mini man page script
cat > sbin/man << EOF
#!/bin/sh
# Simple man page implementation using help
if command -v \$1 >/dev/null 2>&1; then
  clear
  head="\$(echo \$1 | tr 'a-z' 'A-Z')(1)\\t\\t\\tManual page\\n"
  body="\$(\$1 --help 2>&1)\\n\\n"
  printf "\$head\$body" | more
  exit 0
fi
echo "No manual entry for \$1"
EOF

# Create init scripts
cat > etc/init.d/rcS << EOF
#!/bin/sh
. /etc/init.d/init-functions
rc
EOF

# Link rcK to rcS
ln -s /etc/init.d/rcS etc/init.d/rcK

#=======================================================================
# CRON CONFIGURATION
#=======================================================================
# Configure default crontabs
cat > var/spool/cron/crontabs/root << EOF
# Run cron jobs at specific times
15  * * * *   cd / && run-parts /etc/cron/hourly
23  6 * * *   cd / && run-parts /etc/cron/daily
47  6 * * 0   cd / && run-parts /etc/cron/weekly
33  5 1 * *   cd / && run-parts /etc/cron/monthly
EOF

# Create logrotate script
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

#=======================================================================
# INIT SCRIPTS INSTALLER
#=======================================================================
# Create init scripts installer
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

#=======================================================================
# STARTUP SCRIPTS
#=======================================================================
# Define startup services
echo "** Creating startup scripts"
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

#=======================================================================
# COMPRESSED SCRIPTS
#=======================================================================
echo "** Installing compressed scripts"

# GNU DHCP client script
cat > usr/share/udhcpc/default.script << EOF
#!/bin/sh
# udhcpc script for configuring network interfaces with GNU utilities

# Function to setup interface
setup_interface() {
  # Configure interface with IP address and netmask
  ifconfig \$interface \$ip netmask \$subnet

  # If we got a router, add a default route
  if [ -n "\$router" ]; then
    # Delete old default routes
    while route del default gw 0.0.0.0 dev \$interface 2>/dev/null; do
      :
    done
    
    # Add new default route
    for i in \$router; do
      route add default gw \$i dev \$interface
      break
    done
  fi

  # Update /etc/resolv.conf
  if [ -n "\$domain" ]; then
    echo "search \$domain" > /etc/resolv.conf
  else
    echo -n > /etc/resolv.conf
  fi
  
  # Add DNS servers to resolv.conf
  if [ -n "\$dns" ]; then
    for i in \$dns; do
      echo "nameserver \$i" >> /etc/resolv.conf
    done
  fi
}

# Get script parameters
export interface=\$1
export action=\$2

# Handle different actions
case "\$action" in
  deconfig)
    # Bring down interface
    ifconfig \$interface 0.0.0.0
    ;;
    
  bound|renew)
    # Setup interface with received parameters
    setup_interface
    ;;
    
  leasefail|nak)
    # Failed to get lease, bring down interface
    ifconfig \$interface 0.0.0.0
    ;;
    
  *)
    echo "Usage: \$0 INTERFACE {bound|renew|deconfig|leasefail|nak}"
    exit 1
    ;;
esac

exit 0
EOF

# Startup scripts functions
cat > etc/init.d/init-functions << EOF
#!/bin/sh
# Init functions for startup scripts using GNU utilities

# Function to initialize a service
init() {
  case "\$1" in
    start)
      start_service
      ;;
    stop)
      stop_service
      ;;
    restart)
      stop_service
      sleep 1
      start_service
      ;;
    status)
      status_service
      ;;
    *)
      echo "Usage: \$0 {start|stop|restart|status}"
      exit 1
      ;;
  esac
}

# Function to start a service
start_service() {
  echo "Starting \$DESC: \$NAME"
  
  # Check if already running
  if [ -f \$PIDFILE ]; then
    echo "\$NAME is already running (pid \$(cat \$PIDFILE))"
    return 0
  fi
  
  # Start the service
  if [ "\$LOG" ]; then
    \$DAEMON \$PARAMS > /var/log/\$LOG 2>&1 &
  else
    \$DAEMON \$PARAMS &
  fi
  
  # Save PID
  echo \$! > \$PIDFILE
  
  # Check if started successfully
  sleep 1
  if [ -f \$PIDFILE ] && kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
    echo "\$NAME started successfully"
  else
    echo "Failed to start \$NAME"
    rm -f \$PIDFILE
    return 1
  fi
}

# Function to stop a service
stop_service() {
  echo "Stopping \$DESC: \$NAME"
  
  # Check if running
  if [ ! -f \$PIDFILE ]; then
    echo "\$NAME is not running"
    return 0
  fi
  
  # Stop the service
  if [ "\$STOP" ]; then
    \$STOP
  else
    kill \$(cat \$PIDFILE)
  fi
  
  # Wait for process to terminate
  for i in 1 2 3 4 5; do
    if ! kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
      break
    fi
    sleep 1
  done
  
  # Force kill if still running
  if kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
    kill -9 \$(cat \$PIDFILE)
    sleep 1
  fi
  
  # Remove PID file
  rm -f \$PIDFILE
  echo "\$NAME stopped"
}

# Function to check service status
status_service() {
  if [ -f \$PIDFILE ] && kill -0 \$(cat \$PIDFILE) 2>/dev/null; then
    echo "\$NAME is running (pid \$(cat \$PIDFILE))"
  else
    echo "\$NAME is not running"
    rm -f \$PIDFILE
  fi
}

# Function to run startup scripts
rc() {
  # Run all scripts in rc.d directory
  for script in /etc/rc.d/*; do
    if [ -x "\$script" ]; then
      echo "Running \$script"
      \$script start
    fi
  done
}
EOF

#=======================================================================
# FILE PERMISSIONS
#=======================================================================
echo "** Setting file permissions"

# Create empty files
touch proc/mounts var/log/wtmp var/log/lastlog

# Set permissions for security-sensitive files
chmod 640 etc/shadow etc/inittab
chmod 664 var/log/lastlog var/log/wtmp
chmod 600 var/spool/cron/crontabs/root

# Set permissions for GNU utilities
chmod 755 bin/*

# Set permissions for executable scripts and system utilities
chmod 755 usr/sbin/nologin sbin/disban init sbin/man etc/init.d/rcS \
          usr/sbin/logrotate usr/bin/add-rc.d sbin/halt \
          usr/share/udhcpc/default.script
chmod 755 sbin/switch_root sbin/modprobe sbin/insmod

# Set permissions for configuration files
chmod 644 etc/passwd etc/group etc/hostname etc/shells etc/hosts etc/fstab \
          etc/issue etc/motd etc/network/interfaces etc/profile

#=======================================================================
# INITRAMFS CREATION
#=======================================================================
echo "** Building initramfs"

# Create initramfs image
find . | cpio -H newc -o 2> /dev/null | gzip > /mnt/boot/$initrd_file
cd ..

# Set permissions and clean up
chmod 400 /mnt/boot/$initrd_file
rm -r rootfs
umount /mnt

#=======================================================================
# ISO IMAGE CREATION
#=======================================================================
# Build ISO image if enabled
if [ "$build_iso" = "true" ]; then
  echo "** Building ISO image"
  
  # Install required packages
  echo "** Installing required packages for ISO creation"
  apt update && apt install -y xorriso grub-common grub-pc-bin mtools \
    libc6 libdevmapper1.02.1 liblzma5 dosfstools uuid-runtime
  
  # Create temporary directory structure
  iso_dir=$(mktemp -d)
  mkdir -p $iso_dir/boot/grub
  
  # Copy kernel and initramfs to ISO directory
  cp /mnt/boot/$kernel_file $iso_dir/boot/
  cp /mnt/boot/$initrd_file $iso_dir/boot/
  
  # Create GRUB configuration for ISO
  cat > $iso_dir/boot/grub/grub.cfg << EOF
set timeout=5
set default=0

menuentry "$distro_name - $distro_desc (Live)" {
  linux /boot/$kernel_file root=UUID=$uuid rootfstype=ext4 rootwait quiet
  initrd /boot/$initrd_file
  boot
}
EOF
  
  # Create the ISO image
  echo "** Creating ISO image: $iso_filename"
  grub-mkrescue -o $iso_filename $iso_dir
  
  # Clean up temporary files
  rm -rf $iso_dir
  
  echo "** ISO image created: $iso_filename"
fi

#=======================================================================
# COMPLETION
#=======================================================================
printf "\n** $distro_name build completed successfully **\n\n"
