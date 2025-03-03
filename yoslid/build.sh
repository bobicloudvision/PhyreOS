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
busybox="https://busybox.net/downloads/busybox-1.34.1.tar.bz2"
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
# BUSYBOX INSTALLATION
#=======================================================================
# Create files directory if it doesn't exist
[ -d ./files ] || mkdir files

# Check if BusyBox is already compiled
answer="n"
if [ -f files/busybox/busybox ]; then
  printf "** Do you want to use a previously compiled BusyBox? (y/n): "
  read answer
fi

# Compile BusyBox if needed
if [ "$answer" != "y" ]; then
  echo "** BusyBox installation"

  # Install required dependencies
  apt update && apt install -y ca-certificates wget build-essential \
    libncurses5 libncurses5-dev bison flex libelf-dev chrpath gawk \
    texinfo libsdl1.2-dev whiptail diffstat cpio libssl-dev bc

  # Download and extract BusyBox
  cd files/
  rm -r busybox* > /dev/null 2>&1
  wget "$busybox" -O busybox.tar.bz2
  tar -xf busybox.tar.bz2
  rm *.tar.bz2
  mv busybox* busybox
  cd busybox
  
  # Configure BusyBox
  make defconfig
  
  # Modify BusyBox configuration for static build
  sed 's/^.*CONFIG_STATIC.*$/CONFIG_STATIC=y/' -i .config
  sed 's/^CONFIG_MAN=y/CONFIG_MAN=n/' -i .config
  echo "CONFIG_STATIC_LIBGCC=y" >> .config
  
  # Compile BusyBox
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
wipefs -af /dev/$device > /dev/null 2>&1

# Create a new partition
echo "** Preparation of the system partition"
printf "n\np\n${part}\n2048\n\nw\n" | \
  ./files/busybox/busybox fdisk /dev/$device > /dev/null 2>&1

# Format the partition with ext4
echo y | mkfs.ext4 /dev/${device}${part}

# Get the UUID of the new partition
uuid=$(blkid /dev/${device}${part} -sUUID -ovalue)

# Mount the new partition and create boot directory
mount /dev/${device}${part} /mnt
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
  linux /boot/$kernel_file quiet rootdelay=130
  initrd /boot/$initrd_file
  root=PARTUUID=$uuid
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

# Install BusyBox and set up directories with proper permissions
cp ../files/busybox/busybox bin
install -d -m 0750 root
install -d -m 1777 tmp

# Copy required DNS libraries
echo "** Copying system libraries"
for i in $(find /lib/ | grep 'ld-2\|ld-lin\|libc.so\|libnss_dns\|libresolv'); do
    cp ${i} lib
done

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
# Create init script
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
mount -t ext4 UUID=$uuid /mnt/root/
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
    /bin/busybox poweroff
    return 0
fi
/bin/busybox halt
EOF

# Create mini man page script
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

# BusyBox DHCP client script (compressed and base64 encoded)
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

#=======================================================================
# FILE PERMISSIONS
#=======================================================================
echo "** Setting file permissions"

# Create empty files
touch proc/mounts var/log/wtmp var/log/lastlog

# Set permissions for security-sensitive files
chmod 640 etc/shadow etc/inittab
chmod 664 var/log/lastlog var/log/wtmp
chmod 4755 bin/busybox
chmod 600 var/spool/cron/crontabs/root

# Set permissions for executable scripts
chmod 755 usr/sbin/nologin sbin/disban init sbin/man etc/init.d/rcS \
          usr/sbin/logrotate usr/bin/add-rc.d sbin/halt \
          usr/share/udhcpc/default.script

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
  linux /boot/$kernel_file quiet
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