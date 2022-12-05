# proxmox-backup-arm64
Script for building Proxmox Backup Server 2.x for Armbian64 based on Bullseye

## Install build essentials and dependencies
```
apt-get install -y --no-install-recommends \
	build-essential curl ca-certificates sudo git lintian \
	pkg-config libudev-dev libssl-dev libapt-pkg-dev libclang-dev \
	libpam0g-dev
```
## Install ``rustup``
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh -s
source ~/.cargo/env
```

## Start build script
```
./build.sh
```
