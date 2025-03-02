#!/bin/bash

# PhyreOS Repository Server Setup Script
# This script sets up a local web server to serve the PhyreOS repository

set -e

# Load configuration
source ./config.sh

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed."
    echo "Please install Python 3 and try again."
    exit 1
fi

# Create repository directory if it doesn't exist
mkdir -p "$WORKDIR/repo"

# Check if repository has been initialized
if [ ! -f "$WORKDIR/repo/dists/stable/Release" ]; then
    echo "⚠️ Repository not initialized. Creating empty repository structure..."
    mkdir -p "$WORKDIR/repo/dists/stable/main/binary-amd64"
    mkdir -p "$WORKDIR/repo/pool/main"
    
    # Create initial Release file
    cat > "$WORKDIR/repo/dists/stable/Release" << EOF
Origin: PhyreOS
Label: $REPO_NAME
Suite: stable
Codename: $REPO_CODENAME
Architectures: $REPO_ARCH
Components: $REPO_COMPONENTS
Description: PhyreOS Custom Package Repository
EOF

    # Create empty Packages file
    touch "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages"
    gzip -9c "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages" > "$WORKDIR/repo/dists/stable/main/binary-$REPO_ARCH/Packages.gz"
    
    # Generate Release file checksums
    cd "$WORKDIR/repo"
    apt-ftparchive release "dists/stable" >> "dists/stable/Release"
fi

# Start a simple HTTP server
echo "🌐 Starting repository server at http://localhost:8000"
echo "Repository URL: http://localhost:8000"
echo "Add to sources.list: deb [trusted=yes] http://localhost:8000 stable main"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

cd "$WORKDIR/repo"
python3 -m http.server 8000
