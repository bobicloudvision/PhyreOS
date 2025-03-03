# desktop-image.bb
require recipes-core/images/core-image-base.bb

DESCRIPTION = "Now linux is better"
LICENSE = "MIT"

# Install the desktop environment and other packages
IMAGE_INSTALL += " \
    xorg-server \
    xfce4 \
    xfce4-terminal \
    lightdm \
    network-manager \
    gnome-icon-theme"

# Set the image type to ISO
IMAGE_FSTYPES = "iso"