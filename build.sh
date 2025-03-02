#!/bin/bash

set -e

CURRENT_DIR=$(pwd)

# Зареждане на конфигурационния файл
source $CURRENT_DIR/config.sh


# Инсталиране на нужните пакети
echo "📦 Инсталиране на зависимости..."
if [ -f /etc/redhat-release ]; then
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y gcc make flex bison openssl-devel bc elfutils-libelf-devel ncurses-devel xz jq wget cpio xorriso grub2-tools-extra gettext
elif [ -f /etc/debian_version ]; then
    sudo apt update
    sudo apt install -y build-essential flex bison libssl-dev bc libelf-dev libncurses-dev xz-utils jq wget cpio xorriso grub-pc-bin grub-common gettext-base
else
    echo "⚠️ Неподдържана дистрибуция!"
    exit 1
fi

# Изчистване на стари файлове
rm -rf "$WORKDIR"
mkdir -p "$ISODIR/boot/grub"

# Изтегляне и разархивиране на ядрото
echo "⬇️ Изтегляне на Linux ядро версия $KERNEL_VERSION..."
mkdir -p "$WORKDIR/src"
cd "$WORKDIR/src"

if ! wget -c "$KERNEL_URL" -O "linux.tar.xz"; then
    echo "❌ Неуспешно изтегляне на ядрото!"
    exit 1
fi

tar -xf linux.tar.xz
cd linux-*/

# Компилиране на ядрото
echo "🛠️ Компилиране на ядрото..."
make defconfig
make -j$(nproc)

sleep 10  # Изчакване за да се избегне грешка при създаване на ISO образа

cp $WORKDIR/src/linux-*/arch/x86/boot/bzImage $ISODIR/boot/vmlinuz

# Изтегляне и компилиране на BusyBox
echo "⬇️ Изтегляне на BusyBox версия $BUSYBOX_VERSION..."
cd "$WORKDIR/src"
if ! wget -c "$BUSYBOX_URL" -O "busybox.tar.bz2"; then
    echo "❌ Неуспешно изтегляне на BusyBox!"
    exit 1
fi

tar -xjf busybox.tar.bz2
cd busybox-${BUSYBOX_VERSION}

echo "🛠️ Компилиране на BusyBox..."
make defconfig
make -j$(nproc)
make install CONFIG_PREFIX="$ISODIR"

# Създаване на initrd с APT
echo "📦 Създаване на initrd с APT..."

mkdir -p "$WORKDIR/initrd"
mkdir -p "$WORKDIR/initrd/etc/apt"
mkdir -p "$WORKDIR/initrd/var/lib/apt/lists"
mkdir -p "$WORKDIR/initrd/var/cache/apt/archives"
mkdir -p "$WORKDIR/initrd/usr/bin"
mkdir -p "$WORKDIR/initrd/usr/lib"

# Copy APT binaries and libraries from host system
echo "📦 Копиране на APT пакети..."
cp /usr/bin/apt-get "$WORKDIR/initrd/usr/bin/"
cp /usr/bin/apt "$WORKDIR/initrd/usr/bin/"
cp /usr/bin/apt-cache "$WORKDIR/initrd/usr/bin/"
cp /usr/lib/apt "$WORKDIR/initrd/usr/lib/" -r

# Copy required shared libraries
echo "📦 Копиране на споделени библиотеки..."
for bin in apt-get apt apt-cache; do
    for lib in $(ldd /usr/bin/$bin | grep -o '/lib[^ ]*' | sort | uniq); do
        mkdir -p "$WORKDIR/initrd$(dirname $lib)"
        cp $lib "$WORKDIR/initrd$lib"
    done
done

# Set up custom repository
echo "📦 Създаване на структура за хранилище на пакети..."
mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"
mkdir -p "$WORKDIR/repo/pool/main"

# Create repository metadata
echo "📦 Създаване на метаданни за хранилището..."
cat > "$WORKDIR/repo/dists/stable/main/binary-amd64/Release" << EOF
Archive: stable
Component: main
Origin: PhyreOS
Label: PhyreOS Custom Repository
Architecture: amd64
EOF

# Copy init script
cp $CURRENT_DIR/init.sh "$WORKDIR/initrd/init"
chmod +x "$WORKDIR/initrd/init"

# Create the initrd image
( cd "$WORKDIR/initrd" && find . | cpio -o --format=newc ) | gzip > "$ISODIR/boot/initrd.img"

# Създаване на GRUB конфигурация
echo "⚙️ Създаване на GRUB конфигурация..."
# Use envsubst to properly expand variables in the template
envsubst < $CURRENT_DIR/grub.cfg.template > "$ISODIR/boot/grub/grub.cfg"

# Return to the original directory
cd "$CURRENT_DIR"

# Генериране на ISO образ
echo "📀 Генериране на ISO образ: $ISO_NAME..."
grub2-mkrescue -o "$ISO_NAME" "$ISODIR"

echo "✅ ISO образът е готов: $ISO_NAME"
