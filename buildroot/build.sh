sudo apt update
sudo apt install -y build-essential bison flex gettext ncurses-dev texinfo unzip wget cpio rsync python3

git clone https://git.buildroot.net/buildroot
cd buildroot

make defconfig
