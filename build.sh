#!/bin/bash

set -e

CURRENT_DIR=$(pwd)

# Зареждане на конфигурационния файл
source $CURRENT_DIR/config.sh


# Инсталиране на нужните пакети
echo "📦 Инсталиране на зависимости..."
if [ -f /etc/redhat-release ]; then
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y gcc make flex bison openssl-devel bc elfutils-libelf-devel ncurses-devel xz jq wget cpio xorriso grub2-tools-extra
elif [ -f /etc/debian_version ]; then
    sudo apt update
    sudo apt install -y build-essential flex bison libssl-dev bc libelf-dev libncurses-dev xz-utils jq wget cpio xorriso grub-pc-bin grub-common
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

sleep 3  # Изчакване за да се избегне грешка при създаване на ISO образа

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

# Създаване на initrd (минимален)
echo "📦 Създаване на initrd..."

mkdir -p "$WORKDIR/initrd"
cp $CURRENT_DIR/init.sh "$WORKDIR/initrd/init"
chmod +x "$WORKDIR/initrd/init"
( cd "$WORKDIR/initrd" && find . | cpio -o --format=newc ) | gzip > "$ISODIR/boot/initrd.img"

# Създаване на GRUB конфигурация
echo "⚙️ Създаване на GRUB конфигурация..."
cat $CURRENT_DIR/grub.cfg.template > "$ISODIR/boot/grub/grub.cfg"

# Генериране на ISO образ
echo "📀 Генериране на ISO образ: $ISO_NAME..."
grub2-mkrescue -o "$ISO_NAME" "$ISODIR"

echo "✅ ISO образът е готов: $ISO_NAME"
