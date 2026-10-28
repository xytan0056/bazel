#!/usr/bin/env bash
# Runs in the Bazel source checkout, using a verified bootstrap binary.
set -euo pipefail

: "${RELEASE_NAME:?}" "${TARGET_OS:?}" "${TARGET_ARCH:?}"
readonly bootstrap="${BAZEL_BOOTSTRAP:-/tmp/bazel-bootstrap}"

build_args=(build)
if [[ "$TARGET_OS" == linux ]]; then
    export DEBIAN_FRONTEND=noninteractive
    # Older apt versions can report success after an index download fails,
    # leaving install with incompatible package metadata. Refresh both steps
    # on retry, in addition to retrying individual downloads.
    for attempt in 1 2 3; do
        if apt-get -o Acquire::Retries=3 update &&
            apt-get -o Acquire::Retries=3 install --yes --no-install-recommends \
                binutils ca-certificates curl file g++ git patch python3 unzip zip; then
            break
        fi
        if [[ "$attempt" == 3 ]]; then
            echo "Unable to install Linux build dependencies after 3 attempts." >&2
            exit 1
        fi
        sleep 5
    done
    git config --global --add safe.directory /workspace
    build_args+=(--sandbox_tmpfs_path=/tmp)
fi

"$bootstrap" "${build_args[@]}" //src:bazel
mkdir -p output
cp bazel-bin/src/bazel output/bazel

output/bazel "${build_args[@]}" \
    -c opt \
    --stamp \
    --embed_label="$RELEASE_NAME" \
    --workspace_status_command=scripts/ci/build_status_command.sh \
    //src:bazel

artifact="bazel-$RELEASE_NAME-$TARGET_OS-$TARGET_ARCH"
cp bazel-bin/src/bazel "$artifact"
"./$artifact" --version
file "$artifact"
if [[ "$TARGET_OS" == linux ]]; then
    sha256sum "$artifact" > "$artifact.sha256"
    for namespace in GLIBC GLIBCXX CXXABI; do
        readelf --version-info "$artifact" \
            | grep -oE "${namespace}_[0-9.]+" \
            | sort -Vu \
            | tail -n 1
    done
else
    shasum --algorithm 256 "$artifact" > "$artifact.sha256"
fi
