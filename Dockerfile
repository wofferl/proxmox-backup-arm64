FROM debian:bullseye-slim as builder-stage
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
RUN source ~/.cargo/env && ./build.sh

FROM scratch
COPY --from=builder-stage /build/packages/* /
