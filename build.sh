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
		echo "Error package ${package} in version " "${version_test[@]}" " not found" >&2
		return 1
	fi

	file="${dest}/${url##*/}"
	if [ -e "${file}" ]; then
		echo "${package} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package} downloading...${url}" >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}

function git_clone_or_fetch() {
	url=${1}              # url/name.git
	name_git=${url##*/}   # name.git
	name=${name_git%.git} # name

	if [ ! -d "${name}" ]; then
		git clone "${url}"
	else
		git -C "${name}" fetch
	fi
}

function git_clean_and_checkout() {
	commit_id=${1}
	path=${2}
	path_args=()
	if [[ "${path}" != "" ]]; then
		path_args=("-C" "${path}")
	fi

	git "${path_args[@]}" clean -ffdx
	git "${path_args[@]}" reset --hard
	git "${path_args[@]}" checkout "${commit_id}"
}

function load_packages() {
	url=${1}
	curl -sSf -H 'Cache-Control: no-cache' "${url}" |
		gzip -d - |
		awk -F": " '/^(Package|Version|Depends|Filename)/ {
				if($1 == "Package") {
					version="";
					depends="";
					filename="";
					package=$2;
				}
				else if($1 == "Version") {
					version=$2;
				}
				else if($1 == "Depends") {
					depends=$2;
				}
				else if($1 == "Filename") {
					filename=$2;
					print package";"version";"filename";"depends;
				}
			}'
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
		name=${line%%;*}
		line=${line##*${name};}

		if [[ "${name}" == "${package_name}" ]]; then
			version=${line%%;*}
			line=${line##*${version};}
			file=${line%%;*}
			line=${line##*${file};}
			depends=${line}
			if dpkg --compare-versions "${version}" "${version_test[@]}" &&
				dpkg --compare-versions "${version}" '>>' "${version_target}"; then
				if [ -n "$depends" ]; then
					sudo apt satisfy -s "${depends}" >/dev/null 2>&1 || continue
				fi
				version_target=${version}
				file_target=${file}
			fi
		fi
	done <<<"${packages_target}"

	if [ -n "${file_target}" ]; then
		url=${url_base}/${file_target}
		echo "${url}"
	fi
}

function set_package_info() {
	if [ "$GITHUB_ACTION" ]; then
		sed -i "s#^Maintainer:.*#Maintainer: Github Action <github@linux-dude.de>#" debian/control
		sed -i "s#^Homepage:.*#Homepage: https://github.com/wofferl/proxmox-backup-arm64#" debian/control
	else
		sed -i "s#^\(Maintainer.*\)\$#\1\nOrigin: https://github.com/wofferl/proxmox-backup-arm64#" debian/control
	fi
}

file_list=()
function download_release() {
	version=${1:-latest}
	release_url="https://api.github.com/repos/wofferl/proxmox-backup-arm64/releases/${version}"
	echo "Downloading ${version} released files to "${PACKAGES}
	for download_url in $(curl -sSf ${release_url} | sed -n '/browser_download_url/ {/static\|dbgsym/!s/.*\(https[^"]*\)"/\1/p}'); do
		file=$(basename ${download_url})
		if [ -e ${PACKAGES}/${file} ]; then
			echo "${file} already exist"
		else
			echo "Downloading ${file}"
			curl -sSfLO ${download_url} --output-dir ${PACKAGES}
		fi
		file_list+=("${PACKAGES}/${file}")
	done
}

function install_server() {
	if [ "${#file_list[@]}" -gt 0 ]; then
		sudo apt-get install -y \
			"${file_list[@]}"
	else
		echo "No files found!"
	fi
}

SUDO="${SUDO:-sudo -E}"

SCRIPT=$(realpath "${0}")
BASE=$(dirname "${SCRIPT}")
PACKAGES="${BASE}/packages"
PACKAGES_BUILD="${BASE}/packages_build"
PATCHES="${BASE}/patches"
SOURCES="${BASE}/sources"
LOGFILE="build.log"
PACKAGE_ARCH=$(dpkg-architecture -q DEB_BUILD_ARCH)
HOST_ARCH=$(dpkg-architecture -q DEB_HOST_ARCH)
HOST_CPU=$(dpkg-architecture -q DEB_HOST_GNU_CPU)
HOST_SYSTEM=$(dpkg-architecture -q DEB_HOST_GNU_SYSTEM)
BUILD_PACKAGE="server"
BUILD_PROFILES=""
GITHUB_ACTION=""


export DEB_HOST_RUST_TYPE=${HOST_CPU}-unknown-${HOST_SYSTEM}

. /etc/os-release

[ ! -d "${PACKAGES}" ] && mkdir -p "${PACKAGES}"

while [ "$#" -ge 1 ]; do
	case "$1" in
	client)
		BUILD_PACKAGE="client"
		BUILD_PROFILES=${BUILD_PROFILES}",nodoc"
		[[ ${BUILD_PROFILES} =~ nocheck ]] || BUILD_PROFILES=${BUILD_PROFILES}",nocheck"
		export DEB_BUILD_OPTIONS="nocheck"
		;;
	cross)
		PACKAGE_ARCH=arm64
		BUILD_PROFILES=${BUILD_PROFILES}",cross"
		export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=/usr/bin/aarch64-linux-gnu-gcc
		export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUNNER=qemu-aarch64
		export CARGO_BUILD_TARGET=aarch64-unknown-linux-gnu
		export TARGET=aarch64-unknown-linux-gnu
		export PKG_CONFIG=/usr/bin/aarch64-linux-gnu-pkg-config
		export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig/
		export CC=/usr/bin/aarch64-linux-gnu-gcc
		export DEB_HOST_MULTIARCH=aarch64-linux-gnu
		export DEB_HOST_RUST_TYPE=aarch64-unknown-linux-gnu
		;;

	install)
		download_release
		install_server
		exit 0
		;;

	download*)
		if [[ "$1" =~ download=[0-9.-]+ ]]; then
			download_release tags/${1/*=/}
		else
			download_release
		fi
		exit 0
		;;
	github)
		GITHUB_ACTION="true"
		;;
	nocheck)
		[[ ${BUILD_PROFILES} =~ nocheck ]] || BUILD_PROFILES=${BUILD_PROFILES}",nocheck"
		export DEB_BUILD_OPTIONS="nocheck"
		;;
	debug)
		exec &> >(tee "${LOGFILE}")
		echo "$@"
		cat /etc/os-release
		rustc -V
		cargo -V
		set -x
		;;
	*)
		echo "usage $0 [client] [nocheck] [debug] [download]"
		exit 1
		;;
	esac
	shift
done
[ -n "${BUILD_PROFILES}" ] && BUILD_PROFILES="--build-profiles=${BUILD_PROFILES#,}"

if [ ! -d "${PATCHES}" ]; then
	echo "Directory ${PATCHES} is missing! Have you cloned the repository?"
	exit 1
fi

[ ! -d "${PACKAGES_BUILD}" ] && mkdir -p "${PACKAGES_BUILD}"
[ ! -d "${SOURCES}" ] && mkdir -p "${SOURCES}"

echo "Download packages list from proxmox devel repository"
PACKAGES_DEVEL=$(load_packages http://download.proxmox.com/debian/devel/dists/trixie/main/binary-amd64/Packages.gz)
echo "Download packages list from pbs-test repository"
PACKAGES_PBS=$(load_packages http://download.proxmox.com/debian/pbs/dists/trixie/pbs-test/binary-amd64/Packages.gz)

echo "Download dependencies"
EXTJS_VER=(">=" "7~")
PBS_I18N_VER=(">=" "0")
PROXMOX_ACME_VER=(">=" "0")
PROXMOX_WIDGETTOOLKIT_VER=(">=" "3.5.2")
QRCODEJS_VER=(">=" "1.20201119")
if [ "${BUILD_PACKAGE}" = "server" ]; then
	download_package pbs pbs-i18n "${PBS_I18N_VER[@]}" "${PACKAGES}" >/dev/null
	download_package pbs libjs-extjs "${EXTJS_VER[@]}" "${PACKAGES}" >/dev/null
	download_package pbs libjs-qrcodejs "${QRCODEJS_VER[@]}" "${PACKAGES}" >/dev/null
	download_package pbs libproxmox-acme-plugins "${PROXMOX_ACME_VER[@]}" "${PACKAGES}" >/dev/null
	download_package pbs proxmox-widget-toolkit "${PROXMOX_WIDGETTOOLKIT_VER[@]}" "${PACKAGES}" >/dev/null
fi
if [ "${BUILD_PACKAGE}" = "server" ]; then
	packages_install=(
		"$(download_package devel proxmox-widget-toolkit-dev "${PROXMOX_WIDGETTOOLKIT_VER[@]}" "${PACKAGES_BUILD}")"
	)
fi

echo "Install build dependencies"
${SUDO} apt install -y "${packages_install[@]}"

cat <<EOF >rust-toolchain.toml
[toolchain]
channel="stable"
targets = [ "${CARGO_BUILD_TARGET:-$(rustc -vV 2>/dev/null | awk '/^host/ { print $2 }')}" ]
EOF

cd "${SOURCES}"
if [ "${BUILD_PACKAGE}" != "client" ]; then
	PROXMOX_BIOME_VER="2.0.6-2"
	PROXMOX_BIOME_GIT="3c6f4292f32800a1e5d73d8940e5ae6f36af0c40" # 2.0.6-2
	PROXMOX_BIOME_DOWNLOAD_VER=("=" "$PROXMOX_BIOME_VER")
	if [ "${HOST_ARCH}" = "amd64" ]; then
		set +e
		download_package devel proxmox-biome "${PROXMOX_BIOME_DOWNLOAD_VER[@]}" "${PACKAGES_BUILD}"
		set -e
	fi
	if [ ! -e "${PACKAGES_BUILD}/proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb" ]; then
		git_clone_or_fetch https://git.proxmox.com/git/proxmox-biome.git
		git_clean_and_checkout ${PROXMOX_BIOME_GIT} proxmox-biome
		patch -p1 -d proxmox-biome/ <"${PATCHES}/proxmox-biome-build.patch"
		if [ "${HOST_ARCH}" = "arm64" ]; then
			patch -p1 -d proxmox-biome/ <"${PATCHES}/proxmox-biome-arm.patch"
		fi
		cd proxmox-biome
		set_package_info
		${SUDO} apt -y build-dep .
		env -i HOME=${HOME} TERM=${TERM} bash -c 'source /etc/profile; source ~/.cargo/env; env; make deb'
		mv -f proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb "${PACKAGES_BUILD}"
		cd ..
	else
		echo "proxmox-biome up-to-date"
	fi
	if [ -e "${PACKAGES_BUILD}/proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb" ]; then
		${SUDO} apt install -y "${PACKAGES_BUILD}/proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb"
	else
		echo "proxmox-biome dependency missing"
		exit 1
	fi
fi

PROXMOX_BACKUP_VER="4.0.6-2"
PROXMOX_BACKUP_GIT="b1fa35ddf4c0105a1ace14b7ead4391424150459"
PROXMOX_GIT="a6edf8ecfa4a0766f0af7d2b2241d484f93ca4e9"
PATHPATTERNS_GIT="42e5e96e30297da878a4d4b3a7fa52b65c1be0ab" # 1.0.0-1
PXAR_GIT="993c66fcb8819770f279cb9fb4d13f58f367606c"         # 1.0.0-1
PROXMOX_FUSE_GIT="87dbf9bfef9169286263bccffaae3206635ca108" # 1.0.0-1
if [ ! -e "${PACKAGES}/proxmox-backup-${BUILD_PACKAGE}_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_GIT} proxmox
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-fuse.git
	git_clean_and_checkout ${PROXMOX_FUSE_GIT} proxmox-fuse
	git_clone_or_fetch https://git.proxmox.com/git/pxar.git
	git_clean_and_checkout ${PXAR_GIT} pxar
	git_clone_or_fetch https://git.proxmox.com/git/pathpatterns.git
	git_clean_and_checkout ${PATHPATTERNS_GIT} pathpatterns

	git_clone_or_fetch https://git.proxmox.com/git/proxmox-backup.git
	git_clean_and_checkout ${PROXMOX_BACKUP_GIT} proxmox-backup
	sed -i '/dh-cargo\|cargo:native\|rustc:native\|librust-/d' proxmox-backup/debian/control
	sed -i 's/\(latexmk\|proxmox-widget-toolkit-dev\|python3-sphinx\)/\1:all/' proxmox-backup/debian/control
	sed -i '/patch.crates-io/,/pxar/s/^#//' proxmox-backup/Cargo.toml
	# Add missing proxmox-s3-client in 4.0.3-1
	sed -i '/patch.crates-io/aproxmox-s3-client = { path = "../proxmox/proxmox-s3-client" }' proxmox-backup/Cargo.toml
	# Add missing proxmox-shared-cache in 3.2.8-1
	sed -i '/^proxmox-shared-memory.*path/aproxmox-shared-cache = { path = "../proxmox/proxmox-shared-cache" }' proxmox-backup/Cargo.toml
	patch -p1 -d proxmox-backup/ <"${PATCHES}/proxmox-backup-build.patch"
	if [ "${BUILD_PACKAGE}" = "client" ]; then
		sed -i '/proxmox-biome/d' proxmox-backup/debian/control
		patch -p1 -d proxmox-backup/ <"${PATCHES}/proxmox-backup-client.patch"
	fi
	if [ "${PACKAGE_ARCH}" = "arm64" ]; then
		sed -i "s/x86_64-linux-gnu/aarch64-linux-gnu/" proxmox-backup/debian/proxmox-backup-file-restore.install
		sed -i "s/x86_64-linux-gnu/aarch64-linux-gnu/" proxmox-backup/debian/proxmox-backup-file-restore.postinst
		sed -i "s/x86_64-linux-gnu/aarch64-linux-gnu/" proxmox-backup/debian/proxmox-backup-server.install
	fi
	if [[ "${BUILD_PROFILES}" =~ cross ]]; then
		patch -p1 -d proxmox-backup/ <"${PATCHES}/proxmox-backup-cross.patch"
		sed -i 's/\(xindy\|proxmox-biome\)\b/\1:native/' proxmox-backup/debian/control
	fi
	cd proxmox-backup/
	set_package_info
	cargo vendor
	${SUDO} apt -y build-dep -a${PACKAGE_ARCH} ${BUILD_PROFILES} .
	export DEB_VERSION=$(dpkg-parsechangelog -SVersion)
	export DEB_VERSION_UPSTREAM=$(dpkg-parsechangelog -SVersion | cut -d- -f1)
	dpkg-buildpackage -a${PACKAGE_ARCH} -b -us -uc ${BUILD_PROFILES}
	cd ..
	if [ "${BUILD_PACKAGE}" = "client" ]; then
		mv -f proxmox-backup-client_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.deb \
			"${PACKAGES}"
	else
		mv -f proxmox-backup-client{,-static}{,-dbgsym}_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.* \
			proxmox-backup-docs_${PROXMOX_BACKUP_VER}_all.deb \
			proxmox-backup-file-restore{,-dbgsym}_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.* \
			proxmox-backup-server{,-dbgsym}_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.* \
			"${PACKAGES}"
	fi
else
	echo "proxmox-backup up-to-date"
fi

[ "${BUILD_PACKAGE}" = "client" ] && exit 0

PVE_XTERMJS_VER="5.5.0-2"
PVE_XTERMJS_GIT="a29b36079fbaf18586615e26bb615992d1007c7e"
PROXMOX_XTERMJS_GIT="deb32a6c4a21bea0d72059de0835fde504296bf0"
PROXMOX_TERMPROXY_VER="1.1.0"
if [ ! -e "${PACKAGES}/proxmox-termproxy_${PROXMOX_TERMPROXY_VER}_${PACKAGE_ARCH}.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/pve-xtermjs.git
	git_clean_and_checkout ${PVE_XTERMJS_GIT} pve-xtermjs
	patch -p1 -d pve-xtermjs/ <"${PATCHES}/pve-xtermjs-arm.patch"
	[[ "${BUILD_PROFILES}" =~ cross ]] &&
		patch -p1 -d pve-xtermjs/ <"${PATCHES}/pve-xtermjs-cross.patch"
	cd pve-xtermjs/
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	git_clean_and_checkout ${PROXMOX_XTERMJS_GIT} proxmox
	cd termproxy
	set_package_info
	${SUDO} apt -y -a${PACKAGE_ARCH} build-dep .
	BUILD_MODE=release make deb
	cd ..
	cd xterm.js
	make deb
	mv -f pve-xtermjs_${PVE_XTERMJS_VER}_all.deb "${PACKAGES}"
	cd ..
	mv -f proxmox-termproxy_${PROXMOX_TERMPROXY_VER}_${PACKAGE_ARCH}.deb "${PACKAGES}"
else
	echo "pve-xtermjs up-to-date"
fi

PROXMOX_JOURNALREADER_VER="1.5"
PROXMOX_JOURNALREADER_GIT="a3afed6c1a743525b00d514ffc066e523784dcf3"
if [ ! -e "${PACKAGES}/proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_${PACKAGE_ARCH}.deb" ]; then
	git_clone_or_fetch https://git.proxmox.com/git/proxmox-mini-journalreader.git
	git_clean_and_checkout ${PROXMOX_JOURNALREADER_GIT} proxmox-mini-journalreader
	patch -p1 -d proxmox-mini-journalreader/ <${PATCHES}/proxmox-mini-journalreader.patch
	[[ "${BUILD_PROFILES}" =~ cross ]] &&
		patch -p1 -d proxmox-mini-journalreader/ <"${PATCHES}/proxmox-mini-journalreader-cross.patch"
	cd proxmox-mini-journalreader/
	set_package_info
	${SUDO} apt -y -a${PACKAGE_ARCH} build-dep .
	make deb
	mv -f proxmox-mini-journalreader{,-dbgsym}_${PROXMOX_JOURNALREADER_VER}_${PACKAGE_ARCH}.deb "${PACKAGES}"
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi
