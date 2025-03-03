# PhyreOS

PhyreOS is a minimal Linux distribution with APT package management.

## Features

- Based on the latest stable Linux kernel
- Uses BusyBox for basic utilities
- Includes APT package manager
- Custom package repository
- Supports both initrd-only and rootfs boot options

## Building

To build PhyreOS, run:

```bash
./build.sh
```

This will create an ISO image that can be booted in a virtual machine or installed on hardware.

## Package Management

PhyreOS uses the APT package manager from Debian. It includes a custom repository for PhyreOS-specific packages.

### Creating Packages

To create a new package and add it to the repository:

```bash
./create-package.sh <package_name> <version> [description]
```

Example:
```bash
./create-package.sh hello 1.0 "Hello World package"
```

### Setting Up a Local Repository Server

For development and testing, you can set up a local repository server:

```bash
./setup-repo-server.sh
```

This will start a web server on port 8000 serving the repository.

## Using APT in PhyreOS

Once booted into PhyreOS, you can use APT to manage packages:

```bash
# Update package lists
apt-get update

# Install a package
apt-get install <package_name>

# Search for packages
apt-cache search <keyword>
```

## Boot Options

PhyreOS provides two boot options:

1. **initrd boot** - A minimal boot environment that loads entirely into RAM. This is lightweight but doesn't persist changes between reboots.

2. **rootfs boot** - A more complete root filesystem that provides a more traditional Linux environment. This option extracts a rootfs archive to a tmpfs filesystem, providing more space and a more complete system structure.

To select a boot option, use the GRUB menu at startup.
