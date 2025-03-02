#!/bin/bash

# PhyreOS Repository Server Setup Script
# This script sets up a local web server to serve the PhyreOS repository

set -e

# Load configuration
source ./config.sh

# Function to check dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 is required but not installed."
        echo "Please install Python 3 and try again."
        exit 1
    fi
}

# Function to create repository structure
create_repository_structure() {
    echo "📁 Creating repository structure..."
    mkdir -p "$WORKDIR/repo"
    
    # Check if repository has been initialized
    if [ ! -f "$WORKDIR/repo/dists/stable/Release" ]; then
        echo "⚠️ Repository not initialized. Creating empty repository structure..."
        mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"
        mkdir -p "$WORKDIR/repo/pool/main"
        
        # Create initial Release file
        create_release_file
        
        # Create empty Packages file
        create_empty_packages_file
        
        # Generate checksums
        generate_checksums
    fi
}

# Function to create Release file
create_release_file() {
    echo "📝 Creating Release file..."
    cat > "$WORKDIR/repo/dists/stable/Release" << EOF
Origin: PhyreOS
Label: $REPO_NAME
Suite: stable
Codename: $REPO_CODENAME
Architectures: $REPO_ARCH
Components: $REPO_COMPONENTS
Description: PhyreOS Custom Package Repository
EOF
}

# Function to create empty Packages file
create_empty_packages_file() {
    echo "📝 Creating empty Packages file..."
    touch "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages"
    gzip -9c "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages" > "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages.gz"
}

# Function to generate checksums for Release file
generate_checksums() {
    echo "📝 Generating checksums for Release file..."
    cd "$WORKDIR/repo"
    
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

# Function to start HTTP server
start_http_server() {
    echo "🌐 Starting repository server at http://localhost:8000"
    echo "Repository URL: http://localhost:8000"
    echo "Add to sources.list: deb [trusted=yes] http://localhost:8000 stable main"
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo ""

    cd "$WORKDIR/repo"
    python3 -m http.server 8000
}

# Main function
main() {
    check_dependencies
    create_repository_structure
    start_http_server
}

# Run the main function
main
