# proxmox-backup-arm64
Script for building Proxmox Backup Server for Armbian64

## Install build essentials and dependencies
```
 apt-get -y install \
	build-essential curl sudo git lintian \
	pkg-config libudev-dev libssl-dev libapt-pkg-dev libclang-dev \
	libnetaddr-ip-perl libpam0g-dev libcurl4-openssl-dev
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
