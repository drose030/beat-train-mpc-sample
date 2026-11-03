#!/bin/sh
# Cross-compiles a product for the MPC Sample (aarch64 Linux) as one fully static
# musl binary, inside the official Swift container. Xcode's compiler cannot use
# the Static Linux SDK, the swift.org toolchain in the container can.
#
#   scripts/build-linux.sh [product]      default: beattrain-hwtest
#
# Prints the path of the built binary.
set -eu

PRODUCT=${1:-beattrain-hwtest}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SWIFT_IMAGE=swift:6.4.2
SDK_URL=https://download.swift.org/swift-6.4.2-release/static-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz
SDK_CHECKSUM=3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a

docker run --rm \
    -v "$ROOT":/src -w /src \
    -v beattrain-swiftpm:/root/.swiftpm \
    "$SWIFT_IMAGE" sh -euc "
        swift sdk list | grep -q static-linux || swift sdk install '$SDK_URL' --checksum '$SDK_CHECKSUM'
        swift build --swift-sdk aarch64-swift-linux-musl -c release \
            --product '$PRODUCT' --scratch-path .build/linux >&2
        swift build --swift-sdk aarch64-swift-linux-musl -c release \
            --scratch-path .build/linux --show-bin-path
    " | tail -n 1 | sed "s|^/src|$ROOT|; s|\$|/$PRODUCT|"
