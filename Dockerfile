FROM debian:bullseye-slim as builder-stage

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
COPY --from=builder-stage /build/packages/* ./packages/
