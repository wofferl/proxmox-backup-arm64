ARG baseimage=debian:bullseye-slim
FROM ${baseimage} as builder-stage
ARG buildoptions
# workaround for memory bug https://github.com/rust-lang/cargo/issues/10583
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt-get install -y --no-install-recommends \
	build-essential curl ca-certificates sudo git lintian \
	pkg-config libudev-dev libssl-dev libapt-pkg-dev libclang-dev \
	libpam0g-dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh -s -- -y

COPY . /build/
WORKDIR /build

SHELL ["/bin/bash", "-c"]
RUN source ~/.cargo/env && ./build.sh ${buildoptions}

RUN if [[ "${buildoptions}" =~ github ]]; then \
	apt-get -y install \
		/build/packages/proxmox-backup-client_*.deb; \
	if [[ ! "${buildoptions}" =~ "client" ]]; then \
		apt-get -y install \
			/build/packages/proxmox-backup-file-restore_*.deb; \
		apt-get -y install \
			/build/packages/libjs-extjs_*_all.deb \
			/build/packages/libjs-qrcodejs_*_all.deb \
			/build/packages/libproxmox-acme-plugins_*_all.deb \
			/build/packages/pbs-i18n_*_all.deb \
			/build/packages/proxmox-backup-docs_*_all.deb \
			/build/packages/proxmox-backup-server_*.deb \
			/build/packages/proxmox-mini-journalreader_*.deb \
			/build/packages/proxmox-widget-toolkit_*_all.deb \
			/build/packages/pve-xtermjs_*.deb; \
        fi \
    fi

FROM scratch
COPY --from=builder-stage /build/*.log /build/packages/* /
