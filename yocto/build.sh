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

# Create a proper place for your custom recipe
mkdir -p meta-custom/recipes-core/images
cp $CURRENT_DIR/desktop-image.bb meta-custom/recipes-core/images/
#
# Create layer configuration
mkdir -p meta-custom/conf
cp $CURRENT_DIR/bblayers.conf meta-custom/conf/layer.conf

# Add your custom layer to the build
bitbake-layers add-layer meta-custom

# Now build your custom image
bitbake desktop-image

echo "Done"