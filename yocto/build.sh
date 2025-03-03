#sudo apt update
#sudo apt install -y lz4 gawk wget git diffstat unzip \
#    texinfo gcc-multilib build-essential chrpath socat \
#    cpio python3 python3-pip python3-pexpect xz-utils \
#    debianutils iputils-ping python3-git python3-jinja2 \
#    libegl1-mesa libsdl1.2-dev xterm
#

#sudo adduser yocto
#su - yocto

#git clone -b kirkstone git://git.yoctoproject.org/poky.git

CURRENT_DIR=$(pwd)
cd poky
source oe-init-build-env

#bitbake-layers create-layer phyre-os
#bitbake-layers add-layer phyre-os
#bitbake-layers show-layers

# Now build your custom image
bitbake core-image-minimal

echo "Done"