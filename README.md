# proxmox-backup-arm64
Script for building Proxmox Backup Server 2.x for Armbian64 based on Bullseye<br />
At least 4 GB are required for compiling. On devices with low memory, SWAP must be used (see help section).

## Download pre-built packages
You can find unoffical debian packages for bullseye that are created with the build.sh script and github actions at https://github.com/wofferl/proxmox-backup-arm64/releases.

With the script you can also download all files of the latest release at once.
```
./build.sh download
```

## Build manually
### Install build essentials and dependencies
```
apt-get install -y --no-install-recommends \
	build-essential curl ca-certificates sudo git lintian fakeroot \
	pkg-config libudev-dev libssl-dev libapt-pkg-dev libclang-dev \
	libpam0g-dev
```
### Install ``rustup``
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh -s
source ~/.cargo/env
```

### Start build script
```
./build.sh 
```
or 
```
./build.sh client (build only proxmox-backup-client package)
```

The compilation can take several hours.<br />
After that you can find the finished packages in the folder packages/

## Build using docker

You can build arm64 .deb packages using the provided Dockerfile and docker buildx:
```
docker buildx build -o packages --platform linux/arm64 .
```

You can also set build arguments for base image and build.sh options:

```
docker buildx build -o packages --build-arg buildoptions="client debug" --build-arg baseimage=ubuntu:jammy --platform linux/arm64 .
```

Once the docker build is completed, packages will be copied from the docker build image to a folder named `packages` in the root folder.

## Build using cross compiler (experimental)
### Enable multi arch and install build essentials and dependencies
For cross compiling you need to enable multiarch and install the needed build dependencies for the target architecture. For the tests to work qemu-user-binfmt is needed.

```
dpkg --add-architecture arm64
```
```
apt update && apt-get install -y --no-install-recommends \
                build-essential crossbuild-essential-arm64 curl ca-certificates sudo git lintian \
                pkg-config libudev-dev:arm64 libssl-dev:arm64 libapt-pkg-dev:arm64 apt:amd64 \
                libclang-dev libpam0g-dev:arm64 \
                qemu-user-binfmt 
```
(apt:amd64 is necessary because libapt-pkg-dev:arm64 would break the dependencies without it)

### Install ``rustup`` and add target arch
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh -s
source ~/.cargo/env
rustup target add aarch64-unknown-linux-gnu
```

### Start build script
```
./build.sh cross
```

## Install all needed packages
### Server
```
sudo apt install \
  ./libjs-extjs_*_all.deb \
  ./libjs-qrcodejs_*_all.deb \
  ./libproxmox-acme-plugins_*_all.deb \
  ./pbs-i18n_*_all.deb \
  ./proxmox-backup-docs_*_all.deb \
  ./proxmox-backup-server_*_arm64.deb \
  ./proxmox-mini-journalreader_*_arm64.deb \
  ./proxmox-widget-toolkit_*_all.deb \
  ./pve-xtermjs_*_arm64.deb
```

### Client
```
sudo apt install \
  ./proxmox-backup-client_*_arm64.deb \
  # Optional: ./proxmox-backup-file-restore_*_arm64.deb
```

## Help section
### Debugging
you can add the debug option to redirect the complete build process output also to a file (build.log)

```
./build.sh debug
```
### Console commands

to see PBS users:

```
proxmox-backup-manager user list
```

to update root user pwd:

```
proxmox-backup-manager user update root@pam --password {pwd}
```

more info: https://pbs.proxmox.com/docs/user-management.html

### Create SWAP (at least 4G on low memory systems like Raspberry PI)
from https://askubuntu.com/questions/178712/how-to-increase-swap-space/1263160#1263160

Check swap memory:

```
swapon --show or free -h
```

Create and enable 4G swap file:

```
sudo fallocate -l 4G /var/swap
sudo mkswap /var/swap
sudo swapon /var/swap
```
