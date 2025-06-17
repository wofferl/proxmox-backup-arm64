ARG baseimage=debian:bookworm-slim
FROM ${baseimage} as builder-stage
ARG buildoptions
# workaround for memory bug https://github.com/rust-lang/cargo/issues/10583
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt-get install -y --no-install-recommends \
	build-essential curl ca-certificates sudo git lintian \
	pkg-config libudev-dev libssl-dev libapt-pkg-dev libclang-dev \
	libpam0g-dev zlib1g-dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -sSf | sh -s -- -y

COPY . /build/
WORKDIR /build

SHELL ["/bin/bash", "-c"]
RUN source ~/.cargo/env && ./build.sh ${buildoptions}

FROM scratch
COPY --from=builder-stage /build/*.log /build/packages/* /
