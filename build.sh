#!/bin/bash
#
# build script for proxmox backup server on arm64
# https://github.com/wofferl/proxmox-backup-arm64

SUDO="sudo"

[ ! -d packages ] && mkdir packages

PVE_ESLINT_VERSION="7.28.0-1"
PVE_ESLINT_GIT="ef0a5638b025ec9b9e3aa4df61a5b3b6bd471439"

if ! dpkg-query -W -f='${Version}' pve-eslint | grep -q ${PVE_ESLINT_VERSION}; then
	if [ ! -d pve-eslint ]; then
		git clone https://git.proxmox.com/git/pve-eslint.git
	else
		git -C pve-eslint fetch
	fi
	cd pve-eslint
	git checkout ${PVE_ESLINT_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	${SUDO} apt -y install ./pve-eslint_${PVE_ESLINT_VERSION}_all.deb
	cd ..
else
	echo "pve-eslint up-to-date"
fi

PVE_COMMON_VERSION="7.0-14"
PVE_COMMON_GIT="3efa9ecd60825f2c95f3136bdaa3a258b13cdd38"

if ! dpkg-query -W -f='${Version}' libpve-common-perl | grep -q ${PVE_COMMON_VERSION}; then
	if [ ! -d pve-common ]; then
		git clone https://git.proxmox.com/git/pve-common.git
	else
		git -C pve-common fetch
	fi
	cd pve-common/
	git checkout ${PVE_COMMON_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	${SUDO} dpkg -i --force-depends ./libpve-common-perl_${PVE_COMMON_VERSION}_all.deb || exit 0
	cd ..
else
	echo "libpve-common-perl up-to-date"
fi

PROXMOX_ACME_VERSION="1.4.0"
PROXMOX_ACME_GIT="300242d78bd63e91d0bc452e6284dafbec1043b1"

if ! dpkg-query -W -f='${Version}' libproxmox-acme-perl | grep -q ${PROXMOX_ACME_VERSION}; then
	if [ ! -d proxmox-acme ]; then
		git clone https://git.proxmox.com/git/proxmox-acme.git
	else
		git -C proxmox-acme fetch
	fi
	cd proxmox-acme/
	git checkout ${PROXMOX_ACME_GIT}
	make deb || exit 0
	${SUDO} apt -y --fix-broken install ./libproxmox-acme-perl_${PROXMOX_ACME_VERSION}_all.deb ./libproxmox-acme-plugins_${PROXMOX_ACME_VERSION}_all.deb
	cd ..
else
	echo "libproxmox-acme-perl up-to-date"
fi

PROXMOX_WIDGETTOOLKIT_VERSION="3.4-4"
PROXMOX_WIDGETTOOLKIT_GIT="ca867fb10dc048ef8a85f36e8ef5b602276f8bfb"

if ! dpkg-query -W -f='${Version}' proxmox-widget-toolkit-dev | grep -q ${PROXMOX_WIDGETTOOLKIT_VERSION}; then
	if [ ! -d proxmox-widget-toolkit ]; then
		git clone https://git.proxmox.com/git/proxmox-widget-toolkit.git
	else
		git -C proxmox-widget-toolkit fetch
	fi
	cd proxmox-widget-toolkit/
	git checkout ${PROXMOX_WIDGETTOOLKIT_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VERSION}_all.deb ../packages
	${SUDO} apt -y install ./proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VERSION}_all.deb
	cd ..
else
	echo "proxmox-widget-toolkit up-to-date"
fi

PROXMOX_BACKUP_TAG="2.1.2"
PROXMOX_BACKUP_VERSION="2.1.2-1"
PROXMOX_GIT="c0312f3717bd00ace434929e7d3305b058f4aae9"
PROMXOX_FUSE_GIT="0e0966af8886c176d8decfe18cb7ead4db5a83a6"
PXAR_GIT="b203d38bcd399f852f898d24403f3d592e5f75f8"
PATHPATTERNS_GIT="916e41c50e75a718ab7b1b95dc770eed9cd7a403"
PROXMOX_ACME_RS_GIT="fb547f59352155bdc7a9738237e4df8fa0cda10d"
PROXMOX_APT_GIT="c7b17de1b5fec5807921efc9565917c3d6b09417"
PROXMOX_OPENID_GIT="d6e7e2599f5190d38dfab58426ebd0ce6a55dd1e"

if [ ! -e packages/proxmox-backup-server_${PROXMOX_BACKUP_VERSION}_arm64.deb ]; then
	[ ! -d proxmox ] && git clone https://git.proxmox.com/git/proxmox.git || git -C proxmox fetch
	git -C proxmox checkout ${PROXMOX_GIT}
	[ ! -d proxmox-fuse ] && git clone https://git.proxmox.com/git/proxmox-fuse.git || git -C proxmox-fuse fetch
	git -C proxmox-fuse checkout ${PROMXOX_FUSE_GIT}
	[ ! -d pxar ] && git clone https://git.proxmox.com/git/pxar.git || git -C pxar fetch
	git -C pxar checkout ${PXAR_GIT}
	[ ! -d pathpatterns ] && git clone https://git.proxmox.com/git/pathpatterns.git || git -C pathpatterns fetch
	git -C pathpatterns checkout ${PATHPATTERNS_GIT}
	[ ! -d proxmox-acme-rs ] && git clone https://git.proxmox.com/git/proxmox-acme-rs.git || git -C proxmox-acme-rs fetch
	git -C proxmox-acme-rs checkout ${PROXMOX_ACME_RS_GIT}
	[ ! -d proxmox-apt ] && git clone https://git.proxmox.com/git/proxmox-apt.git || git -C proxmox-apt fetch
	git -C proxmox-apt checkout ${PROXMOX_APT_GIT}
	[ ! -d proxmox-openid-rs ] && git clone https://git.proxmox.com/git/proxmox-openid-rs.git || git -C proxmox-openid-rs fetch
	git -C proxmox-openid-rs checkout ${PROXMOX_OPENID_GIT}

	[ ! -d proxmox-backup ] && git clone https://git.proxmox.com/git/proxmox-backup.git || git -C proxmox-backup fetch
	git -C proxmox-backup clean -f
	git -C proxmox-backup checkout .
	git -C proxmox-backup checkout ${PROXMOX_BACKUP_TAG}
	patch -p1 -d proxmox-backup/ < patches/proxmox-backup-arm.patch
	patch -p1 -d proxmox-backup/ < patches/proxmox-backup-compile.patch
	cd proxmox-backup
	cargo vendor || exit 0
	${SUDO} apt -y build-dep .
	dpkg-buildpackage -b -us -uc --no-pre-clean || exit 0
	cd ..
	cp -a proxmox-backup-client_${PROXMOX_BACKUP_VERSION}_arm64.deb \
		proxmox-backup-docs_${PROXMOX_BACKUP_VERSION}_all.deb \
		proxmox-backup-file-restore_${PROXMOX_BACKUP_VERSION}_arm64.deb \
		proxmox-backup-server_${PROXMOX_BACKUP_VERSION}_arm64.deb \
		packages/
else
	echo "proxmox-backup up-to-date"
fi

PROXMOX_XTERMJS_GIT="d3636d45d973e79a05a89c7e7e3d0fec73f6e067"
PVE_XTERMJS_VER="4.12.0-1"
PVE_XTERMJS_GIT="3b087ebf80621a39e2977cad327056ff4b425efe"
if [ ! -e packages/pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb ]; then
	[ ! -d proxmox ] && git clone https://git.proxmox.com/git/proxmox.git || git -C proxmox fetch
	git -C proxmox checkout ${PROXMOX_XTERMJS_GIT}
	[ ! -d pve-xtermjs ] && git clone https://git.proxmox.com/git/pve-xtermjs.git || git -C pve-xtermjs fetch
	git -C pve-xtermjs clean -f
	git -C pve-xtermjs checkout .
	git -C pve-xtermjs checkout ${PVE_XTERMJS_GIT}
	patch -p1 -d pve-xtermjs/ < patches/pve-xtermjs-arm.patch
	cd pve-xtermjs
	make deb || exit 0
	cd ..
	cp -a pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb packages/
else
	echo "pve-xtermjs up-to-date"
fi

PROXMOX_JOURNALREADER_VER="1.2-1"
PROXMOX_JOURNALREADER_GIT="5ce05d16f63b5bddc0ffffa7070c490763eeda22"
if [ ! -e packages/proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_arm64.deb ]; then
	[ ! -d proxmox-mini-journalreader ] && git clone https://git.proxmox.com/git/proxmox-mini-journalreader.git || git -C proxmox-mini-journalreader fetch
	git -C proxmox-mini-journalreader clean -f
	git -C proxmox-mini-journalreader checkout .
	git -C proxmox-mini-journalreader checkout ${PROXMOX_JOURNALREADER_GIT}
	patch -p1 -d proxmox-mini-journalreader/ < patches/proxmox-mini-journalreader.patch
	cd proxmox-mini-journalreader/ 
	make deb || exit 0
	cp -a proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_arm64.deb ../packages
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi


PBS_I18N_VER="2.6-2"
PBS_I18N_GIT="bc0fe9172658e0a203480834275472f120501148"
if [ ! -e packages/pbs-i18n_${PBS_I18N_VER}_all.deb ]; then
	[ ! -d proxmox-i18n ] && git clone https://git.proxmox.com/git/proxmox-i18n.git || git -C proxmox-i18n fetch
	git -C proxmox-i18n checkout ${PBS_I18N_GIT}
	cd proxmox-i18n/
	make deb || exit 0
	cp -a pbs-i18n_${PBS_I18N_VER}_all.deb ../packages/
	cd ..
else
	echo "pbs-i18n up-to-date"
fi

EXTJS_VER="7.0.0-1"
EXTJS_GIT="58b59e2e04ae5cc29a12c10350db15cceb556277"
if [ ! -e packages/libjs-extjs_${EXTJS_VER}_all.deb ]; then
	[ ! -d extjs ] && git clone https://git.proxmox.com/git/extjs.git || git -C extjs fetch
	git -C extjs checkout ${EXTJS_GIT}
	cd extjs/
	make deb || exit 0
	cp -a libjs-extjs_${EXTJS_VER}_all.deb ../packages/
	cd ..
else
	echo "libjs-extjs up-to-date"
fi

QRCODEJS_VER="1.20201119-pve1"
QRCODEJS_GIT="1cc4649f55853d7d890aa444a7a58a8466f10493"
if [ ! -e packages/libjs-qrcodejs_${QRCODEJS_VER}_all.deb ]; then
	[ ! -d libjs-qrcodejs ] && git clone https://git.proxmox.com/git/libjs-qrcodejs.git || git -C libjs-qrcodejs fetch
	git -C libjs-qrcodejs checkout ${QRCODEJS_GIT}
	cd libjs-qrcodejs
	make deb || exit 0
	cp -a libjs-qrcodejs_${QRCODEJS_VER}_all.deb ../packages/
	cd ..
else
	echo "libjs-qrcodejs up-to-date"
fi
