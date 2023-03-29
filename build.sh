#!/bin/bash
#
# build script for proxmox backup server on arm64
# https://github.com/wofferl/proxmox-backup-arm64

set -eu

function download_package() {
	repo=${1}
	package=${2}
	if [ -n "${5}" ]; then
		version_test=("${3}" "${4}")
		dest=${5}
	else
		version_test=('=' "${3}")
		dest=${4}
	fi

	url=$(select_package "${repo}" "${package}" "${version_test[@]}")

	if [ -z "${url}" ]; then
		echo "Error package ${package} in version " "${version_test[@]}" " not found"
		return 1
	fi

	file="${dest}/${url##*/}"
	if [ -e "${file}" ]; then
		echo "${package} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package} downloading..." >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}

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

function load_packages() {
	url=${1}
	curl -sSf "${url}" \
		| gzip -d - \
		| sed '/./{H;$!d} ; x ; s/^.*Package: \([^\n]*\).*Version: \([^\n]*\).*Filename: \([^\n]*\).*$/\1 \2 \3/p'
}

function select_package() {
	repo=${1}
	package_name=${2}
	version_test=("${3}" "${4}")
	url_base=http://download.proxmox.com/debian/${repo}
	if [[ "${repo}" == "pbs" ]]; then
		packages_target=${PACKAGES_PBS}
	elif [[ "${repo}" == "devel" ]]; then
		packages_target=${PACKAGES_DEVEL}
	else
		echo "Unknown repo ${repo}" >&2
		return 1
	fi

	version_target=0.0
	file_target=

	while IFS= read -r line; do
		name=${line%% *}
		if [[ "${name}" == "${package_name}" ]]; then
			version=${line#* }
			version=${version% *}
			file=${line##* }
			if dpkg --compare-versions "${version}" "${version_test[@]}" \
				&& dpkg --compare-versions "${version}" '>>' "${version_target}"; then
				version_target=${version}
				file_target=${file}
			fi
		fi
	done <<<"${packages_target}"

	if [ -z "${file_target}" ]; then
		return 1
	fi
	url=${url_base}/${file_target}
	echo "${url}"
}

SUDO="${SUDO:-sudo -E}"

SCRIPT=$(realpath "${0}")
BASE=$(dirname "${SCRIPT}")
PACKAGES="${BASE}/packages"
PACKAGES_BUILD="${BASE}/packages_build"
PATCHES="${BASE}/patches"
SOURCES="${BASE}/sources"

if [ ! -d "${PATCHES}" ]; then
	echo "Directory ${PATCHES} is missing! Have you cloned the repository?"
	exit 1
fi

[ ! -d "${PACKAGES}" ] && mkdir -p "${PACKAGES}"
[ ! -d "${PACKAGES_BUILD}" ] && mkdir -p "${PACKAGES_BUILD}"
[ ! -d "${SOURCES}" ] && mkdir -p "${SOURCES}"


PACKAGES_DEVEL=$(load_packages http://download.proxmox.com/debian/devel/dists/bullseye/main/binary-amd64/Packages.gz)
PACKAGES_PBS=$(load_packages http://download.proxmox.com/debian/pbs/dists/bullseye/pbs-no-subscription/binary-amd64/Packages.gz)


EXTJS_VER=(">=" "7~")
PBS_I18N_VER=(">=" "0")
PROXMOX_ACME_VER=(">=" "0")
PROXMOX_WIDGETTOOLKIT_VER=(">=" "3.5.2")
PVE_ESLINT_VER=(">=" "7.18.0-1")
QRCODEJS_VER=(">=" "1.20201119")
download_package pbs pbs-i18n "${PBS_I18N_VER[@]}" "${PACKAGES}" >/dev/null
download_package pbs libjs-extjs "${EXTJS_VER[@]}" "${PACKAGES}" >/dev/null
download_package pbs libjs-qrcodejs "${QRCODEJS_VER[@]}" "${PACKAGES}" >/dev/null
download_package pbs libproxmox-acme-plugins "${PROXMOX_ACME_VER[@]}" "${PACKAGES}" >/dev/null
download_package pbs proxmox-widget-toolkit "${PROXMOX_WIDGETTOOLKIT_VER[@]}" "${PACKAGES}" >/dev/null
packages_install=(
	"$(download_package devel proxmox-widget-toolkit-dev "${PROXMOX_WIDGETTOOLKIT_VER[@]}" "${PACKAGES_BUILD}")"
	"$(download_package devel pve-eslint "${PVE_ESLINT_VER[@]}" "${PACKAGES_BUILD}")"
)
${SUDO} apt install -y "${packages_install[@]}"


cd "${SOURCES}"

PROXMOX_BACKUP_VER="2.4.1-1"
PROXMOX_BACKUP_GIT="3da94f2e7429ea1653ed5e61a0f83e67ff02b8be"
PATHPATTERNS_GIT="8a0dce93d535ef04bfa9c8317edc0ef0216e9042" # 0.1.3-1
PROXMOX_ACME_RS_GIT="abc0bdd09d5c3501534510d49da0ae8fa5c05c05" # 0.4.0
PROXMOX_APT_GIT="8a7a719aec23ad98a00bb452f0ced4cbf88ba591" # 0.9.3-1
PROMXOX_FUSE_GIT="8d57fb64f044ea3dcfdef77ed5f1888efdab0708" # 0.1.4
PROXMOX_GIT="32e7d3ccdfd2702dcceea312a6caee7b1565030a"
PROXMOX_OPENID_GIT="ecf59cbb74278ea0e9710466508158ed6a6828c4" # 0.9.9-1
PXAR_GIT="29cbeed3e1b52f5eef455cdfa8b5e93f4e3e88f5" # 0.10.2-1
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
	patch -p1 -d proxmox-backup/ < "${PATCHES}/proxmox-backup-arm.patch"
	cd proxmox-backup/
	cargo vendor
	${SUDO} apt -y build-dep .
	export DEB_VERSION=$(dpkg-parsechangelog -SVersion)
	export DEB_VERSION_UPSTREAM=$(dpkg-parsechangelog -SVersion | cut -d- -f1)
	dpkg-buildpackage -b -us -uc
	cd ..
	cp -a proxmox-backup-client{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-docs_${PROXMOX_BACKUP_VER}_all.deb \
		proxmox-backup-file-restore{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		proxmox-backup-server{,-dbgsym}_${PROXMOX_BACKUP_VER}_arm64.deb \
		"${PACKAGES}"
else
	echo "proxmox-backup up-to-date"
fi

PVE_XTERMJS_VER="4.16.0-2"
PVE_XTERMJS_GIT="8dcff86a32c3ba8754b84e8aabb01369ef3de407"
PROXMOX_XTERMJS_GIT="41862eeb95b70201c47dfd27fca37879e23be3ff"
if [ ! -e "${PACKAGES}/pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_XTERMJS_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/pve-xtermjs.git
	git_clean_and_checkout ${PVE_XTERMJS_GIT} pve-xtermjs
	patch -p1 -d pve-xtermjs/ < "${PATCHES}/pve-xtermjs-arm.patch"
	patch -p1 -d pve-xtermjs/ < "${PATCHES}/pve-xtermjs-fix_already_registered.patch"
	cd pve-xtermjs/
	${SUDO} apt -y build-dep .
	BUILD_MODE=release make deb
	cd ..
	cp -a pve-xtermjs_${PVE_XTERMJS_VER}_arm64.deb "${PACKAGES}"
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
	make deb
	cp -a proxmox-mini-journalreader{,-dbgsym}_${PROXMOX_JOURNALREADER_VER}_arm64.deb "${PACKAGES}"
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi
