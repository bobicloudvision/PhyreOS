#!/bin/bash

# PhyreOS Package Creation Script
# This script creates a Debian package and adds it to the PhyreOS repository

set -e

# Load configuration
source ./config.sh

# Function to check command line arguments
check_arguments() {
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <package_name> <package_version> [description]"
        echo "Example: $0 hello 1.0 'Hello World package'"
        exit 1
    fi
}

# Function to create package directory structure
create_package_structure() {
    local pkg_name="$1"
    local pkg_version="$2"
    local pkg_description="$3"
    local pkg_dir="$4"
    
    echo "📁 Creating package directory structure..."
    mkdir -p "$pkg_dir/DEBIAN"
    mkdir -p "$pkg_dir/usr/bin"
    mkdir -p "$pkg_dir/usr/share/doc/$pkg_name"

    # Create control file
    cat > "$pkg_dir/DEBIAN/control" << EOF
Package: $pkg_name
Version: $pkg_version
Section: base
Priority: optional
Architecture: amd64
Maintainer: PhyreOS Team <admin@phyreos.org>
Description: $pkg_description
EOF

    # Create a simple executable script as an example
    cat > "$pkg_dir/usr/bin/$pkg_name" << EOF
#!/bin/sh
echo "This is $pkg_name version $pkg_version"
EOF
    chmod +x "$pkg_dir/usr/bin/$pkg_name"

    # Create documentation
    cat > "$pkg_dir/usr/share/doc/$pkg_name/README" << EOF
$pkg_name
Version: $pkg_version

$pkg_description

This package was created for PhyreOS.
EOF
}

# Function to build the Debian package
build_package() {
    local pkg_dir="$1"
    local pkg_deb="$2"
    
    echo "📦 Building package $(basename "$pkg_dir")..."
    
    # Create the control.tar.gz
    cd "$pkg_dir/DEBIAN"
    tar czf "$pkg_dir/control.tar.gz" .
    cd "$pkg_dir"
    rm -rf DEBIAN

    # Create the data.tar.gz
    tar czf "$pkg_dir/data.tar.gz" .

    # Create the debian-binary file
    echo "2.0" > "$pkg_dir/debian-binary"

    # Create the .deb package using ar
    cd "$pkg_dir"
    ar rcs "$pkg_deb" debian-binary control.tar.gz data.tar.gz
    cd ..
}

# Function to add package to repository
add_to_repository() {
    local pkg_name="$1"
    local pkg_deb="$2"
    
    echo "📦 Adding package to repository..."
    
    # Create repository structure if it doesn't exist
    mkdir -p "$WORKDIR/repo/pool/main/${pkg_name:0:1}/$pkg_name"
    mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"

    # Move the package to the repository
    mv "$pkg_deb" "$WORKDIR/repo/pool/main/${pkg_name:0:1}/$pkg_name/"
}

# Function to update repository metadata
update_repository_metadata() {
    echo "📦 Updating repository metadata..."
    cd "$WORKDIR/repo"

    # Create Packages file manually
    echo "📦 Creating Packages file..."
    PACKAGES_FILE="dists/stable/main/binary-amd64/Packages"
    > "$PACKAGES_FILE"

    # For each package in the repository
    find pool/main -name "*.deb" | while read pkg_path; do
        pkg_name=$(basename "$pkg_path" | cut -d_ -f1)
        pkg_version=$(basename "$pkg_path" | cut -d_ -f2 | cut -d. -f1)
        
        echo "Package: $pkg_name" >> "$PACKAGES_FILE"
        echo "Version: $pkg_version" >> "$PACKAGES_FILE"
        echo "Architecture: amd64" >> "$PACKAGES_FILE"
        echo "Maintainer: PhyreOS Team <admin@phyreos.org>" >> "$PACKAGES_FILE"
        echo "Filename: $pkg_path" >> "$PACKAGES_FILE"
        echo "Size: $(stat -c%s "$pkg_path")" >> "$PACKAGES_FILE"
        echo "Description: A PhyreOS package" >> "$PACKAGES_FILE"
        echo "" >> "$PACKAGES_FILE"
    done

    # Compress the Packages file
    gzip -9c "$PACKAGES_FILE" > "$PACKAGES_FILE.gz"

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
    generate_checksums
}

# Function to generate checksums for Release file
generate_checksums() {
    echo "📝 Generating checksums for Release file..."
    
    echo "MD5Sum:" >> "dists/stable/Release"
    for file in dists/stable/main/binary-amd64/Packages*; do
        echo " $(md5sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $(echo $file | sed 's|dists/stable/||')" >> "dists/stable/Release"
    done

    echo "SHA1:" >> "dists/stable/Release"
    for file in dists/stable/main/binary-amd64/Packages*; do
        echo " $(sha1sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $(echo $file | sed 's|dists/stable/||')" >> "dists/stable/Release"
    done

    echo "SHA256:" >> "dists/stable/Release"
    for file in dists/stable/main/binary-amd64/Packages*; do
        echo " $(sha256sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $(echo $file | sed 's|dists/stable/||')" >> "dists/stable/Release"
    done
}

# Main function
main() {
    # Parse command line arguments
    check_arguments "$@"
    
    local PACKAGE_NAME="$1"
    local PACKAGE_VERSION="$2"
    local PACKAGE_DESCRIPTION="${3:-A PhyreOS package}"
    
    # Set up paths
    local PACKAGE_DIR="$WORKDIR/packages/$PACKAGE_NAME-$PACKAGE_VERSION"
    local PACKAGE_DEB="$PACKAGE_DIR.deb"
    
    # Create and build the package
    create_package_structure "$PACKAGE_NAME" "$PACKAGE_VERSION" "$PACKAGE_DESCRIPTION" "$PACKAGE_DIR"
    build_package "$PACKAGE_DIR" "$PACKAGE_DEB"
    add_to_repository "$PACKAGE_NAME" "$PACKAGE_DEB"
    update_repository_metadata
    
    echo "✅ Package $PACKAGE_NAME-$PACKAGE_VERSION added to repository"
    echo "Repository is located at $WORKDIR/repo"
}

# Run the main function with all command line arguments
main "$@"
