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

## Raspberry 3B help
Using Raspberry PI OS Lite (64-bit), a port of Debian Bullseye with no desktop

increase SWAP, I used 4G and success compilation
from https://askubuntu.com/questions/178712/how-to-increase-swap-space/1263160#1263160
```
swapon --show
sudo swapoff /var/swap
sudo fallocate -l 4G /var/swap
sudo mkswap /var/swap
sudo swapon /var/swap
swapon --show
```

## After packages compiled (inside "packages" folder) or downloaded, install with command:
from https://github.com/wofferl/proxmox-backup-arm64/issues/8
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

## first login user and password
login to terminal

to see PBS users:
```
proxmox-backup-manager user list
```

to update root user pwd:
```
proxmox-backup-manager user update root@pam --password {pwd}
```

more info: https://pbs.proxmox.com/docs/user-management.html
