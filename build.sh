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

if [ ! -d "${PATCHES}" ]; then
	echo "Directory ${PATCHES} is missing! Have you cloned the repository?"
	exit 1
fi

[ ! -d "${PACKAGES}" ] && mkdir -p "${PACKAGES}"
[ ! -d "${SOURCES}" ] && mkdir -p "${SOURCES}"

cd "${SOURCES}"

PVE_ESLINT_VER="8.23.1-1"
PVE_ESLINT_GIT="857347d600e0ba86451a25e350fbeeef27577b92"
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

PROXMOX_PERL_VER="0.2.1"
PROXMOX_PERL_GIT="d00aa7f0915b7b93500862fba607d41509497c8b"
PROXMOX_ACME_RS_GIT="abc0bdd09d5c3501534510d49da0ae8fa5c05c05"
PROXMOX_APT_GIT="8a7a719aec23ad98a00bb452f0ced4cbf88ba591"
PROXMOX_GIT="d513ef78361cbdb505b4e0e6dbf74b1a10ee987e"
PROXMOX_OPENID_GIT="ce6def219262b5c1f6dbe5440f9f90038bafb3d8"
PROXMOX_PERLMOD_GIT="40d6ec96ea3103b258dce500b88c12a2951f7b95"
PROXMOX_RESOURCE_SCHEDULING_GIT="582cf066d506eb31097098f416f698dd128867c1"
if ! dpkg-query -W -f='${Version}' libproxmox-rs-perl | grep -q ${PROXMOX_PERL_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-perl-rs.git
	git_clean_and_checkout ${PROXMOX_PERL_GIT} proxmox-perl-rs
	cd proxmox-perl-rs
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-acme-rs.git
	git_clean_and_checkout ${PROXMOX_ACME_RS_GIT} proxmox-acme-rs
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-apt.git
	git_clean_and_checkout ${PROXMOX_APT_GIT} proxmox-apt
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-openid-rs.git
	git_clean_and_checkout ${PROXMOX_OPENID_GIT} proxmox-openid-rs
	git_clone_or_fetch https://git.proxmox.com/git/perlmod.git
	git_clean_and_checkout ${PROXMOX_PERLMOD_GIT} perlmod
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-resource-scheduling.git
	git_clean_and_checkout ${PROXMOX_RESOURCE_SCHEDULING_GIT} proxmox-resource-scheduling
	patch -p1 < "${PATCHES}/proxmox-perl-rs-dependencies.patch" || exit 0
	cargo vendor || exit 0
        ${SUDO} apt -y build-dep ./common/pkg ./pmg-rs ./pve-rs
	make pve-deb pmg-deb common-deb || exit 0
	${SUDO} apt -y install ./build/libproxmox-rs-perl_${PROXMOX_PERL_VER}_arm64.deb \
				./build/libpve-rs-perl_0.7.3_arm64.deb \
				./build/libpmg-rs-perl_0.6.2_arm64.deb
	cd ..
else
	echo "libproxmox-rs-perl up-to-date"
fi


PVE_COMMON_VER="7.3-1"
PVE_COMMON_GIT="9d14c9ddcf24a2f20a5ded58d28c3e1657ed3728"
if ! dpkg-query -W -f='${Version}' libpve-common-perl | grep -q ${PVE_COMMON_VER}; then
	git_clone_or_fetch https://git.proxmox.com/git/pve-common.git
	cd pve-common/
	git_clean_and_checkout ${PVE_COMMON_GIT}
	${SUDO} apt -y build-dep .
	make deb || exit 0
	${SUDO} dpkg -i --force-depends ./libpve-common-perl_${PVE_COMMON_VER}_all.deb
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
	${SUDO} apt -y --fix-broken install ./libproxmox-acme-perl_${PROXMOX_ACME_VER}_all.deb \
					 ./libproxmox-acme-plugins_${PROXMOX_ACME_VER}_all.deb
	cd ..
else
	echo "libproxmox-acme-perl up-to-date"
fi

PROXMOX_WIDGETTOOLKIT_VER="3.5.3"
PROXMOX_WIDGETTOOLKIT_GIT="0bba4fc63f488d807c2f8410c49a7a051195a3fd"
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

PROXMOX_BACKUP_VER="2.3.1-1"
PROXMOX_BACKUP_GIT="2abb984b58aca4169fbf9a22ebf302d186f3e062"
PATHPATTERNS_GIT="fda9f89ee0f2229f2863f6e9cfb4fed3b9ce0614"
PROXMOX_ACME_RS_GIT="abc0bdd09d5c3501534510d49da0ae8fa5c05c05"
PROXMOX_APT_GIT="8a7a719aec23ad98a00bb452f0ced4cbf88ba591"
PROMXOX_FUSE_GIT="8d57fb64f044ea3dcfdef77ed5f1888efdab0708"
PROXMOX_GIT="d513ef78361cbdb505b4e0e6dbf74b1a10ee987e"
PROXMOX_OPENID_GIT="ce6def219262b5c1f6dbe5440f9f90038bafb3d8"
PXAR_GIT="729281cd932dd6fd43dcc3539ac48d7d734a55c2"
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


PBS_I18N_VER="2.8-1"
PBS_I18N_GIT="b7ff45c1f2265708d619bb9ec4a8b9e7c3e1be98"
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
