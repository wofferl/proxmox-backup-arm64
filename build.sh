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

SCRIPT=$(realpath "${0}")
BASE=$(dirname "${SCRIPT}")
PACKAGES="${BASE}/packages"
PATCHES="${BASE}/patches"
SOURCES="${BASE}/sources"

[ ! -d "${PACKAGES}" ] && mkdir -p "${PACKAGES}"
[ ! -d "${SOURCES}" ] && mkdir -p "${SOURCES}"

cd "${SOURCES}"

PVE_ESLINT_VER="8.4.0-3"
PVE_ESLINT_GIT="0a9df8d6a9c8d765f2a2bd6b9f467341b5124188"
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

PROXMOX_ACME_VER="1.4.2"
PROXMOX_ACME_GIT="831d879ba508c40835827852951be1d469208b13"
if ! dpkg-query -W -f='${Version}' libproxmox-acme-perl | grep -q ${PROXMOX_ACME_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-acme.git
	cd proxmox-acme/
	git_clean_and_checkout ${PROXMOX_ACME_GIT}
	#${SUDO} apt -y build-dep .  # don't install build-dep, because it will remove libpve-common-perl
	make deb || exit 0
	cp -a libproxmox-acme-plugins_${PROXMOX_ACME_VER}_all.deb "${PACKAGES}"
	${SUDO} apt -y --fix-broken install ./libproxmox-acme-perl_${PROXMOX_ACME_VER}_all.deb ./libproxmox-acme-plugins_${PROXMOX_ACME_VER}_all.deb
	cd ..
else
	echo "libproxmox-acme-perl up-to-date"
fi

PROXMOX_WIDGETTOOLKIT_VER="3.5.1"
PROXMOX_WIDGETTOOLKIT_GIT="3e83971bca2abc2b2921cce7ab597466ce8ce005"
if ! dpkg-query -W -f='${Version}' proxmox-widget-toolkit-dev | grep -q ${PROXMOX_WIDGETTOOLKIT_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-widget-toolkit.git
	cd proxmox-widget-toolkit/
	git_clean_and_checkout ${PROXMOX_WIDGETTOOLKIT_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a proxmox-widget-toolkit_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb \
		proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb \
		"${PACKAGES}"
	${SUDO} apt -y install ./proxmox-widget-toolkit-dev_${PROXMOX_WIDGETTOOLKIT_VER}_all.deb
	cd ..
else
	echo "proxmox-widget-toolkit up-to-date"
fi

PROXMOX_BACKUP_VER="2.2.5-1"
PROXMOX_BACKUP_GIT="c5cd99b15bcf2f93cabcaab5cfea6488daff23a8"
PATHPATTERNS_GIT="916e41c50e75a718ab7b1b95dc770eed9cd7a403"
PROXMOX_ACME_RS_GIT="abc0bdd09d5c3501534510d49da0ae8fa5c05c05"
PROXMOX_APT_GIT="c7b17de1b5fec5807921efc9565917c3d6b09417"
PROMXOX_FUSE_GIT="6dcf34d2fd516aeca57a62ee4657526552ab4630"
PROXMOX_GIT="6e4a43d6837aec3fa3a5f70740716bbf77c296ef"
PROXMOX_OPENID_GIT="0ec392e425a946b018c64e98a4181a22e0e25a2c"
PXAR_GIT="b203d38bcd399f852f898d24403f3d592e5f75f8"
if [ ! -e "${PACKAGES}/proxmox-backup-server_${PROXMOX_BACKUP_VER}_arm64.deb" ]; then
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
	patch -p1 -d proxmox/ < "${PATCHES}/proxmox-no-ksm.patch" || exit 0
	patch -p1 -d proxmox-backup/ < "${PATCHES}/proxmox-backup-arm.patch" || exit 0
	cd proxmox-backup/
	cargo vendor || exit 0
	${SUDO} apt -y build-dep .
	dpkg-buildpackage -b -us -uc || exit 0
	cd ..
	cp -a proxmox-backup-client{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-docs_${PROXMOX_BACKUP_VER}_all.deb \
		proxmox-backup-file-restore{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-server{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		"${PACKAGES}"
else
	echo "proxmox-backup up-to-date"
fi

PVE_XTERMJS_VER="4.16.0-1"
PVE_XTERMJS_GIT="8dcff86a32c3ba8754b84e8aabb01369ef3de407"
PROXMOX_XTERMJS_GIT="41862eeb95b70201c47dfd27fca37879e23be3ff"
if [ ! -e "${PACKAGES}/pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_XTERMJS_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/pve-xtermjs.git
	git_clean_and_checkout ${PVE_XTERMJS_GIT} pve-xtermjs
	patch -p1 -d pve-xtermjs/ < "${PATCHES}/pve-xtermjs-arm.patch" || exit 0
	cd pve-xtermjs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cd ..
	cp -a pve-xtermjs{,-dbgsym}_${PVE_XTERMJS_VER}_arm64.deb "${PACKAGES}"
else
	echo "pve-xtermjs up-to-date"
fi

PROXMOX_JOURNALREADER_VER="1.3-1"
PROXMOX_JOURNALREADER_GIT="09cd4c8e692c5d357fa360e600a34dc3036cda59"
if [ ! -e "${PACKAGES}/proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_arm64.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-mini-journalreader.git
	git_clean_and_checkout ${PROXMOX_JOURNALREADER_GIT} proxmox-mini-journalreader
	patch -p1 -d proxmox-mini-journalreader/ < ${PATCHES}/proxmox-mini-journalreader.patch
	cd proxmox-mini-journalreader/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a proxmox-mini-journalreader{,-dbgsym}_${PROXMOX_JOURNALREADER_VER}_arm64.deb "${PACKAGES}"
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi


PBS_I18N_VER="2.7-2"
PBS_I18N_GIT="bd8a9ba2cc34872d3dd9579e412a19a3b5a05f21"
if [ ! -e "${PACKAGES}/pbs-i18n_${PBS_I18N_VER}_all.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-i18n.git
	git_clean_and_checkout ${PBS_I18N_GIT} proxmox-i18n
	cd proxmox-i18n/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a pbs-i18n_${PBS_I18N_VER}_all.deb "${PACKAGES}"
	cd ..
else
	echo "pbs-i18n up-to-date"
fi

EXTJS_VER="7.0.0-1"
EXTJS_GIT="58b59e2e04ae5cc29a12c10350db15cceb556277"
if [ ! -e "${PACKAGES}/libjs-extjs_${EXTJS_VER}_all.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/extjs.git
	git_clean_and_checkout ${EXTJS_GIT} extjs
	cd extjs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a libjs-extjs_${EXTJS_VER}_all.deb "${PACKAGES}"
	cd ..
else
	echo "libjs-extjs up-to-date"
fi

QRCODEJS_VER="1.20201119-pve1"
QRCODEJS_GIT="1cc4649f55853d7d890aa444a7a58a8466f10493"
if [ ! -e "${PACKAGES}/libjs-qrcodejs_${QRCODEJS_VER}_all.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/libjs-qrcodejs.git
	git_clean_and_checkout ${QRCODEJS_GIT} libjs-qrcodejs
	cd libjs-qrcodejs/
	${SUDO} apt -y build-dep .
	make deb || exit 0
	cp -a libjs-qrcodejs_${QRCODEJS_VER}_all.deb "${PACKAGES}"
	cd ..
else
	echo "libjs-qrcodejs up-to-date"
fi
