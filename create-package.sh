#!/bin/bash

# PhyreOS Package Creation Script
# This script creates a Debian package and adds it to the PhyreOS repository

set -e

# Load configuration
source ./config.sh

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <package_name> <package_version> [description]"
    echo "Example: $0 hello 1.0 'Hello World package'"
    exit 1
fi

PACKAGE_NAME="$1"
PACKAGE_VERSION="$2"
PACKAGE_DESCRIPTION="${3:-A PhyreOS package}"

# Create package directory structure
PACKAGE_DIR="$WORKDIR/packages/$PACKAGE_NAME-$PACKAGE_VERSION"
mkdir -p "$PACKAGE_DIR/DEBIAN"
mkdir -p "$PACKAGE_DIR/usr/bin"
mkdir -p "$PACKAGE_DIR/usr/share/doc/$PACKAGE_NAME"

# Create control file
cat > "$PACKAGE_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $PACKAGE_VERSION
Section: base
Priority: optional
Architecture: amd64
Maintainer: PhyreOS Team <admin@phyreos.org>
Description: $PACKAGE_DESCRIPTION
EOF

# Create a simple executable script as an example
cat > "$PACKAGE_DIR/usr/bin/$PACKAGE_NAME" << EOF
#!/bin/sh
echo "This is $PACKAGE_NAME version $PACKAGE_VERSION"
EOF
chmod +x "$PACKAGE_DIR/usr/bin/$PACKAGE_NAME"

# Create documentation
cat > "$PACKAGE_DIR/usr/share/doc/$PACKAGE_NAME/README" << EOF
$PACKAGE_NAME
Version: $PACKAGE_VERSION

$PACKAGE_DESCRIPTION

This package was created for PhyreOS.
EOF

# Build the package
echo "📦 Building package $PACKAGE_NAME-$PACKAGE_VERSION..."
dpkg-deb --build "$PACKAGE_DIR"

# Create repository structure if it doesn't exist
mkdir -p "$WORKDIR/repo/pool/main/${PACKAGE_NAME:0:1}/$PACKAGE_NAME"
mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"

# Move the package to the repository
mv "$PACKAGE_DIR.deb" "$WORKDIR/repo/pool/main/${PACKAGE_NAME:0:1}/$PACKAGE_NAME/"

# Generate repository metadata
echo "📦 Updating repository metadata..."
cd "$WORKDIR/repo"

# Create Packages file
apt-ftparchive packages "pool/main" > "dists/stable/main/binary-amd64/Packages"
gzip -9c "dists/stable/main/binary-amd64/Packages" > "dists/stable/main/binary-amd64/Packages.gz"

# Create Release file
cat > "dists/stable/Release" << EOF
Origin: PhyreOS
Label: PhyreOS Custom Repository
Suite: stable
Codename: stable
Architectures: amd64
Components: main
Description: PhyreOS Custom Package Repository
EOF

# Generate Release file checksums
apt-ftparchive release "dists/stable" >> "dists/stable/Release"

echo "✅ Package $PACKAGE_NAME-$PACKAGE_VERSION added to repository"
echo "Repository is located at $WORKDIR/repo"
