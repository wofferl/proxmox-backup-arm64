#!/bin/bash
#
# build script for proxmox backup server on arm64
# https://github.com/wofferl/proxmox-backup-arm64

function git_clone_or_fetch() {
	url=${1}  # url/name.git
	name_git=${url##*/}  # name.git
	name=${name_git%.git}  # name

	if [ ! -d "${name}" ]; then
		git clone "${url}"
	else
		git -C "${name}" fetch
	fi
}

function git_clean_and_checkout() {
	commit_id=${1}
	path=${2}
	path_args=( )
	if [[ "${path}" != "" ]]; then
		path_args=( "-C" "${path}" )
	fi

	git "${path_args[@]}" clean -ffdx
	git "${path_args[@]}" reset --hard
	git "${path_args[@]}" checkout "${commit_id}"
}

SUDO="sudo"

[ ! -d packages ] && mkdir packages

PVE_ESLINT_VER="7.28.0-1"
PVE_ESLINT_GIT="ef0a5638b025ec9b9e3aa4df61a5b3b6bd471439"
if ! dpkg-query -W -f='${Version}' pve-eslint | grep -q ${PVE_ESLINT_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/pve-eslint.git
	cd pve-eslint/
	git_clean_and_checkout ${PVE_ESLINT_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	${SUDO} apt -y install ./pve-eslint_${PVE_ESLINT_VER}_all.deb
	cd ..
else
	echo "pve-eslint up-to-date"
fi

PVE_COMMON_VER="7.0-14"
PVE_COMMON_GIT="3efa9ecd60825f2c95f3136bdaa3a258b13cdd38"
if ! dpkg-query -W -f='${Version}' libpve-common-perl | grep -q ${PVE_COMMON_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/pve-common.git
	cd pve-common/
	git_clean_and_checkout ${PVE_COMMON_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	${SUDO} dpkg -i --force-depends ./libpve-common-perl_${PVE_COMMON_VER}_all.deb || exit 0
	cd ..
else
	echo "libpve-common-perl up-to-date"
fi

PROXMOX_ACME_VER="1.4.0"
PROXMOX_ACME_GIT="300242d78bd63e91d0bc452e6284dafbec1043b1"
if ! dpkg-query -W -f='${Version}' libproxmox-acme-perl | grep -q ${PROXMOX_ACME_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-acme.git
	cd proxmox-acme/
	git_clean_and_checkout ${PROXMOX_ACME_GIT}
	#${SUDO} apt -y build-dep .  # don't install build-dep, because it will remove libpve-common-perl
	make deb || exit 0
	cp -a libproxmox-acme-plugins_${PROXMOX_ACME_VER}_all.deb ../packages/
	${SUDO} apt -y --fix-broken install ./libproxmox-acme-perl_${PROXMOX_ACME_VER}_all.deb ./libproxmox-acme-plugins_${PROXMOX_ACME_VER}_all.deb
	cd ..
else
	echo "libproxmox-acme-perl up-to-date"
fi

PROXMOX_WIDGETTOOLKIT_VER="3.4-4"
PROXMOX_WIDGETTOOLKIT_GIT="ca867fb10dc048ef8a85f36e8ef5b602276f8bfb"
if ! dpkg-query -W -f='${Version}' proxmox-widget-toolkit-dev | grep -q ${PROXMOX_WIDGETTOOLKIT_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-widget-toolkit.git
	cd proxmox-widget-toolkit/
	git_clean_and_checkout ${PROXMOX_WIDGETTOOLKIT_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a proxmox-widget-toolkit_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb \
		proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb \
		../packages/
	${SUDO} apt -y install ./proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb
	cd ..
else
	echo "proxmox-widget-toolkit up-to-date"
fi

PROXMOX_BACKUP_VER="2.1.2-1"
PROXMOX_BACKUP_GIT="2.1.2"
PATHPATTERNS_GIT="916e41c50e75a718ab7b1b95dc770eed9cd7a403"
PROXMOX_ACME_RS_GIT="fb547f59352155bdc7a9738237e4df8fa0cda10d"
PROXMOX_APT_GIT="c7b17de1b5fec5807921efc9565917c3d6b09417"
PROMXOX_FUSE_GIT="0e0966af8886c176d8decfe18cb7ead4db5a83a6"
PROXMOX_GIT="c0312f3717bd00ace434929e7d3305b058f4aae9"
PROXMOX_OPENID_GIT="d6e7e2599f5190d38dfab58426ebd0ce6a55dd1e"
PXAR_GIT="b203d38bcd399f852f898d24403f3d592e5f75f8"
if [ ! -e packages/proxmox-backup-server_${PROXMOX_BACKUP_VER}_arm64.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-fuse.git
	git_clean_and_checkout ${PROMXOX_FUSE_GIT} proxmox-fuse
	git_clone_or_fetch https://git.proxmox.com/git/pxar.git
	git_clean_and_checkout ${PXAR_GIT} pxar
	git_clone_or_fetch https://git.proxmox.com/git/pathpatterns.git
	git_clean_and_checkout ${PATHPATTERNS_GIT} pathpatterns
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-acme-rs.git
	git_clean_and_checkout ${PROXMOX_ACME_RS_GIT} proxmox-acme-rs
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-apt.git
	git_clean_and_checkout ${PROXMOX_APT_GIT} proxmox-apt
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-openid-rs.git
	git_clean_and_checkout ${PROXMOX_OPENID_GIT} proxmox-openid-rs

	git_clone_or_fetch https://git.proxmox.com/git/proxmox-backup.git
	git_clean_and_checkout ${PROXMOX_BACKUP_GIT} proxmox-backup
	patch -p1 -d proxmox-backup/ < patches/proxmox-backup-arm.patch
	patch -p1 -d proxmox-backup/ < patches/proxmox-backup-compile.patch
	cd proxmox-backup/
	cargo vendor || exit 0
	${SUDO} apt -y build-dep .
	dpkg-buildpackage -b -us -uc --no-pre-clean || exit 0
	cd ..
	cp -a proxmox-backup-client{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-docs_${PROXMOX_BACKUP_VER}_all.deb \
		proxmox-backup-file-restore{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-server{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		packages/
else
	echo "proxmox-backup up-to-date"
fi

PVE_XTERMJS_VER="4.12.0-1"
PVE_XTERMJS_GIT="3b087ebf80621a39e2977cad327056ff4b425efe"
PROXMOX_XTERMJS_GIT="d3636d45d973e79a05a89c7e7e3d0fec73f6e067"
if [ ! -e packages/pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_XTERMJS_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/pve-xtermjs.git
	git_clean_and_checkout ${PVE_XTERMJS_GIT} pve-xtermjs
	patch -p1 -d pve-xtermjs/ < patches/pve-xtermjs-arm.patch
	cd pve-xtermjs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cd ..
	cp -a pve-xtermjs{,-dbgsym}_${PVE_XTERMJS_VER}_arm64.deb packages/
else
	echo "pve-xtermjs up-to-date"
fi

PROXMOX_JOURNALREADER_VER="1.2-1"
PROXMOX_JOURNALREADER_GIT="5ce05d16f63b5bddc0ffffa7070c490763eeda22"
if [ ! -e packages/proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_arm64.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-mini-journalreader.git
	git_clean_and_checkout ${PROXMOX_JOURNALREADER_GIT} proxmox-mini-journalreader
	patch -p1 -d proxmox-mini-journalreader/ < patches/proxmox-mini-journalreader.patch
	cd proxmox-mini-journalreader/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a proxmox-mini-journalreader{,-dbgsym}_${PROXMOX_JOURNALREADER_VER}_arm64.deb ../packages/
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi


PBS_I18N_VER="2.6-2"
PBS_I18N_GIT="bc0fe9172658e0a203480834275472f120501148"
if [ ! -e packages/pbs-i18n_${PBS_I18N_VER}_all.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-i18n.git
	git_clean_and_checkout ${PBS_I18N_GIT} proxmox-i18n
	cd proxmox-i18n/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a pbs-i18n_${PBS_I18N_VER}_all.deb ../packages/
	cd ..
else
	echo "pbs-i18n up-to-date"
fi

EXTJS_VER="7.0.0-1"
EXTJS_GIT="58b59e2e04ae5cc29a12c10350db15cceb556277"
if [ ! -e packages/libjs-extjs_${EXTJS_VER}_all.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/extjs.git
	git_clean_and_checkout ${EXTJS_GIT} extjs
	cd extjs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a libjs-extjs_${EXTJS_VER}_all.deb ../packages/
	cd ..
else
	echo "libjs-extjs up-to-date"
fi

QRCODEJS_VER="1.20201119-pve1"
QRCODEJS_GIT="1cc4649f55853d7d890aa444a7a58a8466f10493"
if [ ! -e packages/libjs-qrcodejs_${QRCODEJS_VER}_all.deb ]; then
	git_clone_or_fetch https://git.proxmox.com/git/libjs-qrcodejs.git
	git_clean_and_checkout ${QRCODEJS_GIT} libjs-qrcodejs
	cd libjs-qrcodejs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a libjs-qrcodejs_${QRCODEJS_VER}_all.deb ../packages/
	cd ..
else
	echo "libjs-qrcodejs up-to-date"
fi
