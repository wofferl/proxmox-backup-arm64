#!/bin/bash
#
# Build script for Proxmox Backup Server on ARM64
# https://github.com/qemus/proxmox-backup-arm64

set -eu

function download_package() {
	repo=${1}
	package=${2}
    if [ -n "${5:-}" ]; then
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

function get_base() {
	local repo="$1"

	if [[ "${repo}" == "pbs" ]]; then
		echo "${PACKAGES_PBS}"
	elif [[ "${repo}" == "devel" ]]; then
		echo "${PACKAGES_DEVEL}"
	elif [[ "${repo}" == "pve" ]]; then
		echo "${PACKAGES_PVE}"
	else
		echo "Unknown repo ${repo}" >&2
		exit 1
	fi

	return 0
}

function download_package_by_upstream_version() {
	repo=${1}
	package_name=${2}
	upstream_version=${3}
	dest=${4}

	url_base=http://download.proxmox.com/debian/${repo}
	packages_target=$(get_base "${repo}")
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

			# Match Debian revisions and binNMUs for the requested upstream version
			case "${version}" in
				"${upstream_version}"|"${upstream_version}"-*|"${upstream_version}"+*|"${upstream_version}"~*) ;;
				*) continue ;;
			esac

			if dpkg --compare-versions "${version}" '>>' "${version_target}"; then
				# Do not pre-filter packages by simulating their dependencies here.
				version_target=${version}
				file_target=${file}
			fi
		fi
	done <<<"${packages_target}"

	if [ -z "${file_target}" ]; then
		return 1
	fi

	url=${url_base}/${file_target}
	file="${dest}/${url##*/}"
	if [ -e "${file}" ]; then
		echo "${package_name} ${version_target} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package_name} ${version_target} downloading...${url}" >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}

function download_package_with_fallback() {
	repo=${1}
	package=${2}
	dest=${3}
	shift 3

	for version in "$@"; do
		[ -n "${version}" ] || continue

		# First try an exact Debian package version.
		if file=$(download_package "${repo}" "${package}" "${version}" "${dest}" 2>/dev/null); then
			echo "${file}"
			return 0
		fi

		# Then try the same value as an upstream version and accept Debian revisions
		if file=$(download_package_by_upstream_version "${repo}" "${package}" "${version}" "${dest}" 2>/dev/null); then
			echo "${file}"
			return 0
		fi
	done

	echo "Error: package ${package} not found in ${repo} for any requested version: $*" >&2
	return 1
}


function download_package_prefix_no_deps() {
	repo=${1}
	package_name=${2}
	upstream_version=${3}
	dest=${4}

	url_base=http://download.proxmox.com/debian/${repo}
	packages_target=$(get_base "${repo}")
	version_target=""
	file_target=""

	while IFS=';' read -r name version file depends; do
		[[ "${name}" == "${package_name}" ]] || continue

		case "${version}" in
			"${upstream_version}"|"${upstream_version}"-*|"${upstream_version}"+*|"${upstream_version}"~*) ;;
			*) continue ;;
		esac

		if [ -z "${version_target}" ] || dpkg --compare-versions "${version}" '>>' "${version_target}"; then
			version_target=${version}
			file_target=${file}
		fi
	done <<<"${packages_target}"

	if [ -z "${file_target}" ]; then
		echo "Error: package ${package_name} not found in ${repo} for upstream version ${upstream_version}" >&2
		echo "Available ${package_name} versions in ${repo}:" >&2
		while IFS=';' read -r name version file depends; do
			[[ "${name}" == "${package_name}" ]] && echo "  ${version}" >&2
		done <<<"${packages_target}"
		return 1
	fi

	url=${url_base}/${file_target}
	file="${dest}/${url##*/}"
	if [ -e "${file}" ]; then
		echo "${package_name} ${version_target} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package_name} ${version_target} downloading...${url}" >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}


function download_package_max_upstream_no_deps() {
	repo=${1}
	package_name=${2}
	max_upstream_version=${3}
	dest=${4}

	url_base=http://download.proxmox.com/debian/${repo}
	packages_target=$(get_base "${repo}")
	version_target=""
	file_target=""
	upstream_target=""

	while IFS=';' read -r name version file depends; do
		[[ "${name}" == "${package_name}" ]] || continue
		[ -n "${version}" ] || continue

		# Compare by upstream part, so a repository version like 1.1.2 is accepted
		# when the requested source version is 1.1.4, but 1.1.5 is not.
		upstream=${version%%-*}
		if ! dpkg --compare-versions "${upstream}" le "${max_upstream_version}"; then
			continue
		fi

		if [ -z "${version_target}" ] || dpkg --compare-versions "${version}" '>>' "${version_target}"; then
			version_target=${version}
			upstream_target=${upstream}
			file_target=${file}
		fi
	done <<<"${packages_target}"

	if [ -z "${file_target}" ]; then
		echo "Error: package ${package_name} not found in ${repo} with upstream <= ${max_upstream_version}" >&2
		echo "Available ${package_name} versions in ${repo}:" >&2
		while IFS=';' read -r name version file depends; do
			[[ "${name}" == "${package_name}" ]] && echo "  ${version}" >&2
		done <<<"${packages_target}"
		return 1
	fi

	if [ "${upstream_target}" != "${max_upstream_version}" ]; then
		echo "Warning: using ${package_name} ${version_target}; requested source upstream is ${max_upstream_version}" >&2
	else
		echo "Using ${package_name} ${version_target}" >&2
	fi

	url=${url_base}/${file_target}
	file="${dest}/${url##*/}"
	if [ -e "${file}" ]; then
		echo "${package_name} ${version_target} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package_name} ${version_target} downloading...${url}" >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}


function download_arch_all_package_satisfying() {
	repo=${1}
	package_name=${2}
	relation=${3}
	required_version=${4}
	dest=${5}

	url_base=http://download.proxmox.com/debian/${repo}
	packages_target=$(get_base "${repo}")
	version_target=""
	file_target=""

	while IFS=';' read -r name version file depends; do
		[[ "${name}" == "${package_name}" ]] || continue
		[ -n "${version}" ] || continue

		# Only auto-download Architecture:all packages. The package lists are
		# amd64 indices, so downloading Architecture:any packages here would
		# accidentally pull amd64 binaries into an ARM64 release.
		[[ "${file##*/}" == *_all.deb ]] || continue

		if [ -n "${relation}" ] && [ -n "${required_version}" ]; then
			dpkg --compare-versions "${version}" "${relation}" "${required_version}" || continue
		fi

		if [ -z "${version_target}" ] || dpkg --compare-versions "${version}" '>>' "${version_target}"; then
			version_target=${version}
			file_target=${file}
		fi
	done <<<"${packages_target}"

	[ -n "${file_target}" ] || return 1

	url=${url_base}/${file_target}
	file="${dest}/${url##*/}"

	if [ -e "${file}" ]; then
		echo "${package_name} ${version_target} up-to-date" >&2
		echo "${file}"
		return 0
	fi

	echo "${package_name} ${version_target} downloading runtime dependency...${url}" >&2
	curl -sSfL "${url}" -o "${file}"
	echo "${file}"
}

function download_runtime_arch_all_dependency() {
	package_name=${1}
	relation=${2:-}
	required_version=${3:-}
	dest=${4}

	# Try the project-specific repositories first, then the shared devel repo.
	for repo in pbs pve devel; do
		if file=$(download_arch_all_package_satisfying "${repo}" "${package_name}" "${relation}" "${required_version}" "${dest}" 2>/dev/null); then
			echo "${file}"
			return 0
		fi
	done

	return 1
}

function download_runtime_arch_all_dependencies() {
	if [ "$#" -eq 0 ]; then
		return 0
	fi

	echo "Resolving Architecture:all runtime dependencies from built package metadata"

	local deb fields line dep package_name relation required_version

	for deb in "$@"; do
		[ -e "${deb}" ] || continue

		fields="$(dpkg-deb -f "${deb}" Pre-Depends Depends Recommends 2>/dev/null || true)"
		[ -n "${fields}" ] || continue

		while IFS= read -r line; do
			# Use the first alternative. If that alternative is not in a Proxmox
			# repo as Architecture:all, it is simply ignored.
			dep="${line%%|*}"

			# trim whitespace
			dep="${dep#"${dep%%[![:space:]]*}"}"
			dep="${dep%"${dep##*[![:space:]]}"}"
			[ -n "${dep}" ] || continue

			package_name="${dep%% *}"
			package_name="${package_name%%:*}"
			[ -n "${package_name}" ] || continue

			relation=""
			required_version=""

			version_re='\\(([^[:space:]]+)[[:space:]]+([^)]*)\\)'
			if [[ "${dep}" =~ ${version_re} ]]; then
				relation="${BASH_REMATCH[1]}"
				required_version="${BASH_REMATCH[2]}"
			fi

			download_runtime_arch_all_dependency "${package_name}" "${relation}" "${required_version}" "${PACKAGES}" >/dev/null || true
		done < <(printf '%s\n' "${fields}" | tr ',' '\n')
	done
}

function dependency_constraint_from_deb() {
	deb=${1}
	wanted=${2}

	fields="$(dpkg-deb -f "${deb}" Pre-Depends Depends Recommends 2>/dev/null || true)"
	[ -n "${fields}" ] || return 1

	local line dep alt package_name relation required_version version_re
	while IFS= read -r line; do
		# Check every alternative, not only the first one, because packages may use
		# alternatives for helper packages.
		while IFS='|' read -r alt; do
			dep="${alt}"
			dep="${dep#"${dep%%[![:space:]]*}"}"
			dep="${dep%"${dep##*[![:space:]]}"}"
			[ -n "${dep}" ] || continue

			package_name="${dep%% *}"
			package_name="${package_name%%:*}"
			[ "${package_name}" = "${wanted}" ] || continue

			relation=""
			required_version=""
			version_re='\(([^[:space:]]+)[[:space:]]+([^)]*)\)'
			if [[ "${dep}" =~ ${version_re} ]]; then
				relation="${BASH_REMATCH[1]}"
				required_version="${BASH_REMATCH[2]}"
			fi

			printf '%s;%s\n' "${relation}" "${required_version}"
			return 0
		done <<<"${line}"
	done < <(printf '%s\n' "${fields}" | tr ',' '\n')

	return 1
}

function package_version_satisfying() {
	repo=${1}
	package_name=${2}
	relation=${3:-}
	required_version=${4:-}

	packages_target=$(get_base "${repo}")
	version_target=""
	while IFS=';' read -r name version file depends; do
		[[ "${name}" == "${package_name}" ]] || continue
		[ -n "${version}" ] || continue

		if [ -n "${relation}" ] && [ -n "${required_version}" ]; then
			dpkg --compare-versions "${version}" "${relation}" "${required_version}" || continue
		fi

		if [ -z "${version_target}" ] || dpkg --compare-versions "${version}" '>>' "${version_target}"; then
			version_target=${version}
		fi
	done <<<"${packages_target}"

	[ -n "${version_target}" ] || return 1
	echo "${version_target}"
}

function resolve_commit_for_package_version() {
	version=${1}
	repo_path=${2}
	package_name=${3}

	# BinNMUs such as 1.2.3-1+b1 do not normally appear in source changelogs.
	source_version=${version%%+*}
	upstream=${source_version%%-*}

	for pattern in "${source_version}" "${version}" "${upstream}"; do
		for tag in $(git -C "${repo_path}" tag -l "*${pattern}*" 2>/dev/null); do
			commit=$(git -C "${repo_path}" rev-list -n1 "${tag}" 2>/dev/null || true)
			if [ -n "${commit}" ]; then
				echo "${commit}"
				return 0
			fi
		done
	done

	# Search all Debian changelogs in the repository. Some Proxmox repos contain
	# multiple packages below subdirectories, for example pve-xtermjs/termproxy.
	local changelog commit
	while IFS= read -r changelog; do
		commit=$(git -C "${repo_path}" log --all --format="%H" -1 -S "${package_name} (${source_version}" -- "${changelog}" 2>/dev/null || true)
		[ -n "${commit}" ] && { echo "${commit}"; return 0; }

		commit=$(git -C "${repo_path}" log --all --format="%H" -1 -S "${package_name} (${upstream}" -- "${changelog}" 2>/dev/null || true)
		[ -n "${commit}" ] && { echo "${commit}"; return 0; }
	done < <(git -C "${repo_path}" ls-files '*debian/changelog' 2>/dev/null)

	commit=$(git -C "${repo_path}" log --all --format="%H" -1 --grep="bump version to ${source_version}" 2>/dev/null || true)
	[ -n "${commit}" ] && { echo "${commit}"; return 0; }
	commit=$(git -C "${repo_path}" log --all --format="%H" -1 --grep="bump version to ${upstream}" 2>/dev/null || true)
	[ -n "${commit}" ] && { echo "${commit}"; return 0; }

	return 1
}

function latest_package_version() {
	repo=${1}
	package_name=${2}

	packages_target=$(get_base "${repo}")
	version_target=""
	while IFS=';' read -r name version file depends; do
		[[ "${name}" == "${package_name}" ]] || continue
		[ -n "${version}" ] || continue
		if [ -z "${version_target}" ] || dpkg --compare-versions "${version}" '>>' "${version_target}"; then
			version_target=${version}
		fi
	done <<<"${packages_target}"

	[ -n "${version_target}" ] || return 1
	echo "${version_target}"
}

function download_package_latest() {
	repo=${1}
	package=${2}
	dest=${3}
	version=$(latest_package_version "${repo}" "${package}")
	download_package "${repo}" "${package}" "${version}" "${dest}"
}

function resolve_commit_for_debian_version() {
	version=${1}
	repo_path=${2}
	package_name=${3:-}
	upstream=${version%%-*}

	for tag in $(git -C "${repo_path}" tag -l "*${version}*" 2>/dev/null; git -C "${repo_path}" tag -l "*${upstream}*" 2>/dev/null); do
		commit=$(git -C "${repo_path}" rev-list -n1 "${tag}" 2>/dev/null || true)
		if [ -n "${commit}" ]; then
			echo "${commit}"
			return 0
		fi
	done

	if [ -n "${package_name}" ]; then
		commit=$(git -C "${repo_path}" log --all --format="%H" -1 -S "${package_name} (${version}" -- debian/changelog 2>/dev/null || true)
		[ -n "${commit}" ] && { echo "${commit}"; return 0; }
		commit=$(git -C "${repo_path}" log --all --format="%H" -1 -S "${package_name} (${upstream}" -- debian/changelog 2>/dev/null || true)
		[ -n "${commit}" ] && { echo "${commit}"; return 0; }
	fi

	commit=$(git -C "${repo_path}" log --all --format="%H" -1 --grep="bump version to ${version}" -- debian/changelog 2>/dev/null || true)
	[ -n "${commit}" ] && { echo "${commit}"; return 0; }
	commit=$(git -C "${repo_path}" log --all --format="%H" -1 --grep="bump version to ${upstream}" -- debian/changelog 2>/dev/null || true)
	[ -n "${commit}" ] && { echo "${commit}"; return 0; }

	return 1
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

resolve_commit() {
    local version=$1
    local repo_path=$2
    local package_name=$3

    local version_stripped=${version%%-*}
    local commit

    # Tags
    for tag in $(git -C "${repo_path}" tag -l "*${version_stripped}*" 2>/dev/null); do
        commit=$(git -C "${repo_path}" rev-list -n1 "${tag}" 2>/dev/null)
        [ -n "${commit}" ] && echo "${commit}" && return 0
    done

    # Common Proxmox bump commit pattern
    commit=$(
        git -C "${repo_path}" log \
            --all \
            --format="%H" \
            -1 \
            --grep="bump version to ${version_stripped}" \
            -- debian/changelog 2>/dev/null
    )

    [ -n "${commit}" ] && echo "${commit}" && return 0

    # Changelog entry search
    commit=$(
        git -C "${repo_path}" log \
            --all \
            --format="%H" \
            -1 \
            -S "${package_name} (${version_stripped}" \
            -- debian/changelog 2>/dev/null
    )

    [ -n "${commit}" ] && echo "${commit}" && return 0

    commit=$(
        git -C "${repo_path}" log \
            --all \
            --format="%H" \
            -1 \
            --grep="${package_name} (${version}" \
            -- debian/changelog 2>/dev/null
    )

    [ -n "${commit}" ] && echo "${commit}" && return 0

    if [ "${version_stripped}" != "${version}" ]; then
        commit=$(
            git -C "${repo_path}" log \
                --all \
                --format="%H" \
                -1 \
                --grep="${package_name} (${version_stripped}" \
                -- debian/changelog 2>/dev/null
        )

        [ -n "${commit}" ] && echo "${commit}" && return 0
    fi

    return 1
}

resolve_dependency_repo_commit() {
	local source_commit=${1}
	local source_path=${2}
	local dependency_repo_path=${3}
	local dependency_crate=${4:-proxmox-sys}
	local dependency_version commit source_date

	# Read dependency crate version from Cargo.toml at the source commit.
	dependency_version="$(
		git -C "${source_path}" show "${source_commit}:Cargo.toml" 2>/dev/null |
			sed -n "s/.*${dependency_crate}.*version[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
			head -1
	)"

	if [ -n "${dependency_version}" ]; then
		# Try to find a matching tag in the dependency repository.
		for tag in $(git -C "${dependency_repo_path}" tag -l "*${dependency_version}*" 2>/dev/null); do
			commit="$(git -C "${dependency_repo_path}" rev-list -n1 "${tag}" 2>/dev/null || true)"
			if [ -n "${commit}" ]; then
				echo "${commit}"
				return 0
			fi
		done
	fi

	# Fall back to newest dependency repo commit at or before source commit date.
	source_date="$(git -C "${source_path}" show -s --format=%ci "${source_commit}" 2>/dev/null || true)"
	if [ -n "${source_date}" ]; then
		commit="$(git -C "${dependency_repo_path}" log --all --format="%H" -1 --before="${source_date}" 2>/dev/null || true)"
		if [ -n "${commit}" ]; then
			echo "${commit}"
			return 0
		fi
	fi

	return 1
}

function resolve_commit_before() {
	source_commit=${1}
	source_path=${2}
	target_path=${3}

	# Pick the newest commit in target_path at or before source_commit's date.
	# This keeps bundled/nested Proxmox checkouts aligned with the project that uses them
	# without needing to manually maintain a second hardcoded commit hash.
	source_date=$(git -C "${source_path}" show -s --format=%ci "${source_commit}" 2>/dev/null || true)
	if [ -n "${source_date}" ]; then
		commit=$(git -C "${target_path}" log --all --format="%H" -1 --before="${source_date}" 2>/dev/null || true)
		if [ -n "${commit}" ]; then
			echo "${commit}"
			return 0
		fi
	fi

	return 1
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

	packages_target=$(get_base "${repo}")
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
				# Do not pre-filter packages by simulating their dependencies here.
				# The local build root might not yet have all repos/arches enabled,
				# which can make apt satisfy reject an otherwise valid downloadable package.
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
		sed -i "s#^Maintainer:.*#Maintainer: Github Action <no-reply@github.com>#" debian/control
		sed -i "s#^Homepage:.*#Homepage: https://github.com/qemus/proxmox-backup-arm64#" debian/control
	else
		sed -i "s#^\(Maintainer.*\)\$#\1\nOrigin: https://github.com/qemus/proxmox-backup-arm64#" debian/control
	fi
}

file_list=()
function download_release() {
	version=${1:-latest}
	release_url="https://api.github.com/repos/qemus/proxmox-backup-arm64/releases/${version}"

	echo "Downloading ${version} released files to ${PACKAGES}"

	mapfile -t download_urls < <(
		curl -sSfL "${release_url}" |
			jq -r '
				.assets[]
				| select(.name | test("static|dbgsym") | not)
				| .browser_download_url
			'
	)

	if [ "${#download_urls[@]}" -eq 0 ]; then
		echo "Error: no release assets found for ${version}" >&2
		return 1
	fi

	for download_url in "${download_urls[@]}"; do

		file=$(basename "${download_url}")
		
			echo "${file} already exists"
		else
			echo "Downloading ${file}"
			curl -sSfL "${download_url}" -o "${PACKAGES}/${file}"
		fi

        [[ "$file" == *"dbgsym"* ]] && continue
        [[ "$file" == "proxmox-backup-client"* ]] && continue

		file_list+=("${PACKAGES}/${file}")
	done
}

function install_server() {
	if [ "${#file_list[@]}" -eq 0 ]; then
		echo "Error: no files found to install" >&2
		return 1
	fi

	${SUDO} apt-get install -y "${file_list[@]}"
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
	cross*)
	    if [[ "$1" =~ cross=[0-9.-]+ ]]; then
			PROXMOX_PB_VER="${1#cross=}"
		fi
	
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

	install*)
		if [[ "$1" =~ install=[0-9.-]+ ]]; then
			download_release tags/${1/*=/}
		else
			download_release
		fi
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
		echo "usage $0 [client] [cross] [nocheck] [debug] [download] [install]"
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

[ ! -d "${SOURCES}" ] && mkdir -p "${SOURCES}"
[ ! -d "${PACKAGES_BUILD}" ] && mkdir -p "${PACKAGES_BUILD}"

echo "Download packages list from proxmox devel repository"
PACKAGES_DEVEL=$(load_packages http://download.proxmox.com/debian/devel/dists/trixie/main/binary-amd64/Packages.gz)
echo "Download packages list from pbs repositories"
PACKAGES_PBS="$(
	load_packages http://download.proxmox.com/debian/pbs/dists/trixie/pbs-test/binary-amd64/Packages.gz
	load_packages http://download.proxmox.com/debian/pbs/dists/trixie/pbs-no-subscription/binary-amd64/Packages.gz
)"
echo "Download packages list from PVE repository"
PACKAGES_PVE=$(load_packages http://download.proxmox.com/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages.gz)

echo "Download dependencies"
if [ "${BUILD_PACKAGE}" = "server" ]; then
	# Build/runtime helper packages are selected dynamically from the loaded
	# repository metadata, instead of pinning minimum versions in this script.
	download_package_latest pbs pbs-i18n "${PACKAGES}" >/dev/null || true
	libjs_extjs="$(download_package_latest pbs libjs-extjs "${PACKAGES}")"
	libjs-qrcodejs="$(download_package_latest pbs libjs-qrcodejs "${PACKAGES}")"
	proxmox_widget_toolkit="$(download_package_latest pbs proxmox-widget-toolkit "${PACKAGES}")"
	download_package_latest pbs libproxmox-acme-plugins "${PACKAGES}" >/dev/null || true

	packages_install=(
		"${libjs_extjs}"
	    "${libjs-qrcodejs}"
		"${proxmox_widget_toolkit}"
		"$(download_package_latest devel proxmox-widget-toolkit-dev "${PACKAGES_BUILD}")"
	)
fi

echo "Install build dependencies"
${SUDO} apt install -y "${packages_install[@]}"

cd "${SOURCES}"

if [ "${BUILD_PACKAGE}" != "client" ]; then

	PROXMOX_BIOME_VER="$(latest_package_version devel proxmox-biome)"
	echo "Using proxmox-biome package version: ${PROXMOX_BIOME_VER}"

	if [ "${HOST_ARCH}" = "amd64" ]; then
		download_package devel proxmox-biome "${PROXMOX_BIOME_VER}" "${PACKAGES_BUILD}" || true
	fi

	if [ ! -e "${PACKAGES_BUILD}/proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb" ]; then
	
		git_clone_or_fetch https://git.proxmox.com/git/proxmox-biome.git
		PROXMOX_BIOME_GIT=$(resolve_commit_for_debian_version "${PROXMOX_BIOME_VER}" proxmox-biome proxmox-biome || true)

		if [ -z "${PROXMOX_BIOME_GIT}" ]; then
			echo "Error: could not resolve proxmox-biome commit for version ${PROXMOX_BIOME_VER}" >&2
			exit 1
		fi

		echo "Using proxmox-biome commit: ${PROXMOX_BIOME_GIT}"
		git_clean_and_checkout "${PROXMOX_BIOME_GIT}" proxmox-biome

		patch -p1 -d proxmox-biome/ <"${PATCHES}/proxmox-biome-build.patch"

		if [ "${HOST_ARCH}" = "arm64" ]; then
			patch -p1 -d proxmox-biome/ <"${PATCHES}/proxmox-biome-arm.patch"
		fi

		cd proxmox-biome
		set_package_info
		${SUDO} apt -y build-dep .

		env -i HOME="${HOME}" TERM="${TERM}" bash -c \
			'source /etc/profile; source ~/.cargo/env; make deb'

		biome_deb="$(
			find "${SOURCES}/proxmox-biome" \
				-maxdepth 2 \
				-type f \
				-name "proxmox-biome_${PROXMOX_BIOME_VER}_${HOST_ARCH}.deb" \
				-print -quit
		)"

		if [ -z "${biome_deb}" ]; then
			echo "Error: proxmox-biome .deb not found" >&2
			find "${SOURCES}/proxmox-biome" -maxdepth 3 -type f -name 'proxmox-biome*.deb' -ls >&2
			exit 1
		fi

		mv -f "${biome_deb}" "${PACKAGES_BUILD}/"
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

PROXMOX_BACKUP_VER="${PROXMOX_BACKUP_VER:-4.2.1}"
PROXMOX_BACKUP_VER="${PROXMOX_BACKUP_VER%%-*}"
PROXMOX_BACKUP_GIT=""
PROXMOX_GIT=""

PATHPATTERNS_VER="$(latest_package_version devel librust-pathpatterns-dev)"
PXAR_VER="$(latest_package_version devel librust-pxar-dev)"
PROXMOX_FUSE_VER="$(latest_package_version devel librust-proxmox-fuse-dev)"

PXAR_GIT=$(resolve_commit_for_debian_version "${PXAR_VER}" pxar pxar || true)
PATHPATTERNS_GIT=$(resolve_commit_for_debian_version "${PATHPATTERNS_VER}" pathpatterns pathpatterns || true)
PROXMOX_FUSE_GIT=$(resolve_commit_for_debian_version "${PROXMOX_FUSE_VER}" proxmox-fuse proxmox-fuse || true)

for name in PATHPATTERNS PXAR PROXMOX_FUSE; do
  git_var="${name}_GIT"
  ver_var="${name}_VER"
  if [ -z "${!git_var}" ]; then
    echo "Error: could not resolve ${name} commit for version ${!ver_var}" >&2
    exit 1
  fi
done

if [ -e "${PACKAGES}/proxmox-backup-${BUILD_PACKAGE}_${PROXMOX_BACKUP_VER}_${PACKAGE_ARCH}.deb" ]; then
  echo "proxmox-backup up-to-date" && exit 0
fi

git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
git_clone_or_fetch https://git.proxmox.com/git/proxmox-backup.git

git_clone_or_fetch https://git.proxmox.com/git/pxar.git
git_clone_or_fetch https://git.proxmox.com/git/proxmox-fuse.git
git_clone_or_fetch https://git.proxmox.com/git/pathpatterns.git

echo "Resolving commit hashes for version ${PROXMOX_BACKUP_VER}..."

PROXMOX_BACKUP_GIT=$(resolve_commit "${PROXMOX_BACKUP_VER}" proxmox-backup proxmox-backup) || true
if [ -z "${PROXMOX_BACKUP_GIT}" ]; then
  echo "Error: Could not resolve proxmox-backup commit for version ${PROXMOX_BACKUP_VER}" >&2
  exit 1
fi

echo "Using proxmox-backup commit: ${PROXMOX_BACKUP_GIT}"

PROXMOX_GIT=$(resolve_dependency_repo_commit "${PROXMOX_BACKUP_GIT}" proxmox-backup proxmox proxmox-sys) || true
if [ -z "${PROXMOX_GIT}" ]; then
  echo "Error: Could not resolve proxmox commit for version ${PROXMOX_BACKUP_VER}" >&2
  exit 1
fi

echo "Using Proxmox commit: ${PROXMOX_GIT}"

git_clean_and_checkout ${PROXMOX_GIT} proxmox
git_clean_and_checkout ${PROXMOX_BACKUP_GIT} proxmox-backup

git_clean_and_checkout ${PXAR_GIT} pxar
git_clean_and_checkout ${PROXMOX_FUSE_GIT} proxmox-fuse
git_clean_and_checkout ${PATHPATTERNS_GIT} pathpatterns

# Use the project's Rust toolchain file when present. If the source does not
# ship one, fall back to the currently installed rustup toolchain instead of
# hardcoding a compiler version here.
if [ -f proxmox-backup/rust-toolchain.toml ]; then
	cp proxmox-backup/rust-toolchain.toml "${BASE}/rust-toolchain.toml"
else
	cat <<EOF >"${BASE}/rust-toolchain.toml"
[toolchain]
channel="$(rustc -vV 2>/dev/null | awk '/^release:/ { print $2 }')"
targets = [ "${CARGO_BUILD_TARGET:-$(rustc -vV 2>/dev/null | awk '/^host:/ { print $2 }')}" ]
EOF
fi

sed -i '/dh-cargo\|cargo:native\|rustc:native\|librust-/d' proxmox-backup/debian/control
sed -i 's/\(latexmk\|proxmox-widget-toolkit-dev\|python3-sphinx\)/\1:all/' proxmox-backup/debian/control
sed -i '/patch.crates-io/,/pxar/s/^#//' proxmox-backup/Cargo.toml

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

[ "${BUILD_PACKAGE}" = "client" ] && exit 0

PVE_XTERMJS_VER="$(latest_package_version pve pve-xtermjs)"

# Download pve-xtermjs first, then use its package metadata to determine which
# proxmox-termproxy version should be built. This avoids hardcoding both the
# xtermjs commit and the termproxy version.
echo "Using pve-xtermjs package version: ${PVE_XTERMJS_VER}"
if [ ! -e "${PACKAGES}/pve-xtermjs_${PVE_XTERMJS_VER}_all.deb" ]; then
	echo "Downloading Architecture:all pve-xtermjs package"
	pve_xtermjs_deb="$(download_package pve pve-xtermjs "${PVE_XTERMJS_VER}" "${PACKAGES}")"
else
	echo "pve-xtermjs up-to-date"
	pve_xtermjs_deb="${PACKAGES}/pve-xtermjs_${PVE_XTERMJS_VER}_all.deb"
fi

termproxy_constraint="$(dependency_constraint_from_deb "${pve_xtermjs_deb}" proxmox-termproxy || true)"
if [ -n "${termproxy_constraint}" ]; then
	termproxy_relation="${termproxy_constraint%%;*}"
	termproxy_required_version="${termproxy_constraint#*;}"
	PROXMOX_TERMPROXY_VER="$(package_version_satisfying pve proxmox-termproxy "${termproxy_relation}" "${termproxy_required_version}")"
	echo "Using proxmox-termproxy package version from pve-xtermjs dependency: ${PROXMOX_TERMPROXY_VER}"
else
	PROXMOX_TERMPROXY_VER="$(latest_package_version pve proxmox-termproxy)"
	echo "Warning: pve-xtermjs does not declare proxmox-termproxy dependency; using latest available ${PROXMOX_TERMPROXY_VER}" >&2
fi

git_clone_or_fetch https://git.proxmox.com/git/pve-xtermjs.git
PVE_XTERMJS_GIT="$(resolve_commit_for_package_version "${PROXMOX_TERMPROXY_VER}" pve-xtermjs proxmox-termproxy || true)"
if [ -z "${PVE_XTERMJS_GIT}" ]; then
	echo "Error: could not resolve pve-xtermjs commit containing proxmox-termproxy ${PROXMOX_TERMPROXY_VER}" >&2
	echo "Available changelog heads:" >&2
	git -C pve-xtermjs ls-files '*debian/changelog' | while read -r changelog; do
		echo "--- ${changelog}" >&2
		git -C pve-xtermjs show "HEAD:${changelog}" 2>/dev/null | head -5 >&2 || true
	done
	exit 1
fi

echo "Using pve-xtermjs commit for proxmox-termproxy ${PROXMOX_TERMPROXY_VER}: ${PVE_XTERMJS_GIT}"
git_clean_and_checkout ${PVE_XTERMJS_GIT} pve-xtermjs

if [ ! -e "${PACKAGES}/proxmox-termproxy_${PROXMOX_TERMPROXY_VER}_${PACKAGE_ARCH}.deb" ]; then
	patch -p1 -d pve-xtermjs/ <"${PATCHES}/pve-xtermjs-arm.patch"
	[[ "${BUILD_PROFILES}" =~ cross ]] && patch -p1 -d pve-xtermjs/ <"${PATCHES}/pve-xtermjs-cross.patch"
	cd pve-xtermjs/
	git_clone_or_fetch https://git.proxmox.com/git/proxmox.git
	PROXMOX_XTERMJS_GIT="$(resolve_commit_before "${PVE_XTERMJS_GIT}" . proxmox || true)"
	if [ -z "${PROXMOX_XTERMJS_GIT}" ]; then
		echo "Error: could not derive Proxmox commit for pve-xtermjs ${PVE_XTERMJS_GIT}" >&2
		exit 1
	fi
	echo "Using pve-xtermjs Proxmox commit: ${PROXMOX_XTERMJS_GIT}"
	git_clean_and_checkout ${PROXMOX_XTERMJS_GIT} proxmox
	cd termproxy
	set_package_info
	${SUDO} apt -y -a${PACKAGE_ARCH} build-dep .
	BUILD_MODE=release make deb
	cd ../..
	termproxy_deb="$(find "${SOURCES}/pve-xtermjs" -maxdepth 2 -type f -name "proxmox-termproxy_${PROXMOX_TERMPROXY_VER}_${PACKAGE_ARCH}.deb" -print -quit)"
	if [ -z "${termproxy_deb}" ]; then
		echo "Error: proxmox-termproxy .deb not found" >&2
		find "${SOURCES}/pve-xtermjs" -maxdepth 3 -type f -name 'proxmox-termproxy*.deb' -ls >&2
		exit 1
	fi
	mv -f "${termproxy_deb}" "${PACKAGES}/"
	rm -f "${SOURCES}/pve-xtermjs"/proxmox-termproxy-dbgsym_*.deb "${SOURCES}/pve-xtermjs"/termproxy/proxmox-termproxy-dbgsym_*.deb
else
	echo "proxmox-termproxy up-to-date"
fi

git_clone_or_fetch https://git.proxmox.com/git/proxmox-mini-journalreader.git
PROXMOX_JOURNALREADER_GIT="$(git -C proxmox-mini-journalreader log --all --format='%H' -1 -- debian/changelog)"
if [ -z "${PROXMOX_JOURNALREADER_GIT}" ]; then
	echo "Error: could not resolve proxmox-mini-journalreader commit" >&2
	exit 1
fi

git_clean_and_checkout ${PROXMOX_JOURNALREADER_GIT} proxmox-mini-journalreader
PROXMOX_JOURNALREADER_VER="$(cd proxmox-mini-journalreader && dpkg-parsechangelog -SVersion)"
echo "Using proxmox-mini-journalreader package version: ${PROXMOX_JOURNALREADER_VER}"

if [ ! -e "${PACKAGES}/proxmox-mini-journalreader_${PROXMOX_JOURNALREADER_VER}_${PACKAGE_ARCH}.deb" ]; then
	patch -p1 -d proxmox-mini-journalreader/ <${PATCHES}/proxmox-mini-journalreader.patch
	[[ "${BUILD_PROFILES}" =~ cross ]] &&
		patch -p1 -d proxmox-mini-journalreader/ <"${PATCHES}/proxmox-mini-journalreader-cross.patch"
	cd proxmox-mini-journalreader/
	set_package_info
	${SUDO} apt -y -a${PACKAGE_ARCH} build-dep .
	make deb
    journalreader_deb="$(
      find "${SOURCES}/proxmox-mini-journalreader" \
        -maxdepth 3 \
        -type f \
        -name "proxmox-mini-journalreader_*_${PACKAGE_ARCH}.deb" \
        ! -name "*-dbgsym_*" \
        -print -quit
    )"	
    if [ -z "${journalreader_deb}" ]; then
		echo "Error: proxmox-mini-journalreader .deb not found" >&2
		find "${SOURCES}/proxmox-mini-journalreader" -maxdepth 3 -type f -name 'proxmox-mini-journalreader*.deb' -ls >&2
		exit 1
	fi
	mv -f "${journalreader_deb}" "${PACKAGES}/"
	cd ..
else
	echo "proxmox-mini-journalreader up-to-date"
fi
