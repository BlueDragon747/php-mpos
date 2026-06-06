#!/usr/bin/env bash
# Install the six configured daemon binaries into MPOS_INSTALL_ROOT/bin/.
#
# Default mode pulls prebuilt Docker images and extracts their binaries.
# Set MPOS_PULL_DAEMON_IMAGES=0 to clone/fetch the upstream 0.25.2 daemon
# repos on this host and build native Ubuntu 24 binaries instead. Test
# installs can also set MPOS_LOCAL_DAEMON_REPO_ROOT to build from already
# copied source repos.
#
# Mirrors the Eliopool testnet stack's image-pull mode.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_BIN="${MPOS_INSTALL_ROOT}/bin"
INSTALL_LIB="${MPOS_INSTALL_ROOT}/lib"
MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
MPOS_PULL_DAEMON_IMAGES="${MPOS_PULL_DAEMON_IMAGES:-1}"
MPOS_DAEMON_SOURCE_REF="${MPOS_DAEMON_SOURCE_REF:-0.25.2}"
MPOS_DAEMON_BUILD_ROOT="${MPOS_DAEMON_BUILD_ROOT:-/root/blakestream-daemon-builds}"
MPOS_LOCAL_DAEMON_REPO_ROOT="${MPOS_LOCAL_DAEMON_REPO_ROOT:-}"
MPOS_DAEMON_BUILD_JOBS="${MPOS_DAEMON_BUILD_JOBS:-}"
MPOS_DAEMON_HARDENED_RELEASE="${MPOS_DAEMON_HARDENED_RELEASE:-1}"
mkdir -p "$INSTALL_BIN" "$INSTALL_LIB"

# (image_repo, source_dir, upstream_repo, daemon, cli, tx)
COIN_TUPLES=(
    "blakecoin|Blakecoin-0.25.2|https://github.com/BlueDragon747/Blakecoin.git|blakecoind|blakecoin-cli|blakecoin-tx"
    "blakebitcoin|BlakeBitcoin-0.25.2|https://github.com/BlakeBitcoin/BlakeBitcoin.git|blakebitcoind|blakebitcoin-cli|blakebitcoin-tx"
    "electron|Electron-ELT-0.25.2|https://github.com/BlueDragon747/Electron-ELT.git|electrond|electron-cli|electron-tx"
    "lithium|lithium-0.25.2|https://github.com/BlueDragon747/lithium.git|lithiumd|lithium-cli|lithium-tx"
    "photon|Photon-0.25.2|https://github.com/BlueDragon747/photon.git|photond|photon-cli|photon-tx"
    "universalmolecule|universalmolecule-0.25.2|https://github.com/BlueDragon747/universalmol.git|universalmoleculed|universalmolecule-cli|universalmolecule-tx"
)

sync_upstream_repo() {
    local repo="$1" source_dir="$2" repo_url="$3"
    local source_path="${MPOS_DAEMON_BUILD_ROOT}/${source_dir}"

    mkdir -p "$MPOS_DAEMON_BUILD_ROOT"
    if [ -d "${source_path}/.git" ]; then
        say "updating ${repo} source at ${source_path}"
        git -C "$source_path" fetch --depth 1 origin "$MPOS_DAEMON_SOURCE_REF"
        git -C "$source_path" checkout -B "$MPOS_DAEMON_SOURCE_REF" FETCH_HEAD
        git -C "$source_path" reset --hard FETCH_HEAD
    else
        say "cloning ${repo} source from ${repo_url}"
        rm -rf "$source_path"
        git clone --depth 1 --branch "$MPOS_DAEMON_SOURCE_REF" "$repo_url" "$source_path"
    fi
    chmod +x "${source_path}/build.sh"
}

if [ "$MPOS_PULL_DAEMON_IMAGES" = "0" ] || [ -n "$MPOS_LOCAL_DAEMON_REPO_ROOT" ]; then
    if [ -z "$MPOS_DAEMON_BUILD_JOBS" ]; then
        cores="$(nproc 2>/dev/null || echo 2)"
        MPOS_DAEMON_BUILD_JOBS=$(( cores > 1 ? cores - 1 : 1 ))
    fi

    source_root="$MPOS_LOCAL_DAEMON_REPO_ROOT"
    if [ -z "$source_root" ]; then
        source_root="$MPOS_DAEMON_BUILD_ROOT"
        say "building daemons from upstream repos at ${MPOS_DAEMON_SOURCE_REF}"
    else
        say "building daemons from ${source_root}"
    fi

    for row in "${COIN_TUPLES[@]}"; do
        IFS='|' read -r repo source_dir repo_url daemon cli tx <<< "$row"
        if [ -z "$MPOS_LOCAL_DAEMON_REPO_ROOT" ]; then
            sync_upstream_repo "$repo" "$source_dir" "$repo_url"
        fi
        source_path="${source_root}/${source_dir}"
        output_path="${source_path}/outputs/Ubuntu-24"

        [ -x "${source_path}/build.sh" ] || {
            echo "ERROR: missing executable build.sh in ${source_path}" >&2
            exit 1
        }

        say "building ${repo} with ${MPOS_DAEMON_BUILD_JOBS} jobs"
        (
            cd "$source_path"
            HARDENED_RELEASE="$MPOS_DAEMON_HARDENED_RELEASE" \
                OUTPUT_BASE="${source_path}/outputs" \
                ./build.sh --native --daemon --no-docker --jobs "$MPOS_DAEMON_BUILD_JOBS"
        )

        for binary in "$daemon" "$cli" "$tx"; do
            [ -x "${output_path}/${binary}" ] || {
                echo "ERROR: expected ${output_path}/${binary} after ${repo} build" >&2
                exit 1
            }
            install -m 0755 "${output_path}/${binary}" "${INSTALL_BIN}/${binary}"
        done
    done

    "${INSTALL_BIN}/blakecoind" --version >/dev/null
    say "local-built daemons present and link-OK"
    exit 0
fi

for row in "${COIN_TUPLES[@]}"; do
    IFS='|' read -r repo _source_dir _repo_url daemon cli tx <<< "$row"
    image="${MPOS_DOCKER_HUB}/${repo}:${MPOS_IMAGE_TAG}"
    say "pulling ${image}"
    docker pull -q "${image}" >/dev/null
    cid=$(docker create "${image}")
    docker cp "${cid}:/usr/local/bin/${daemon}" "${INSTALL_BIN}/${daemon}"
    docker cp "${cid}:/usr/local/bin/${cli}"    "${INSTALL_BIN}/${cli}"
    docker cp "${cid}:/usr/local/bin/${tx}"     "${INSTALL_BIN}/${tx}"
    docker rm -f "${cid}" >/dev/null
    chmod 755 "${INSTALL_BIN}/${daemon}" "${INSTALL_BIN}/${cli}" "${INSTALL_BIN}/${tx}"
done

# Runtime libs — extracted from the blakecoin image so the native binaries
# can find the same ABI versions they were linked against.
say "extracting daemon runtime libs"
cid=$(docker create "${MPOS_DOCKER_HUB}/blakecoin:${MPOS_IMAGE_TAG}")
tmpdir=$(mktemp -d)
trap 'docker rm -f "${cid}" >/dev/null 2>&1 || true; rm -rf "${tmpdir}"' EXIT
image_tar="${tmpdir}/image.tar"
libs_list="${tmpdir}/runtime-libs.txt"
docker export "${cid}" > "$image_tar"
tar -tf "$image_tar" | grep -E \
    'usr/lib/x86_64-linux-gnu/(libboost_(filesystem|program_options|thread|chrono|system)|libminiupnpc|libevent(-2\.1|_core-2\.1|_pthreads-2\.1)|libzmq)\.so\.' \
    > "$libs_list" || true
if [ -s "$libs_list" ]; then
    tar -xf "$image_tar" -C "$tmpdir" -T "$libs_list"
    while IFS= read -r lib; do
        cp -P "${tmpdir}/${lib}" "${INSTALL_LIB}/"
    done < "$libs_list"
else
    say "no extra daemon runtime libs found in ${MPOS_DOCKER_HUB}/blakecoin:${MPOS_IMAGE_TAG}"
fi
docker rm -f "${cid}" >/dev/null
rm -rf "${tmpdir}"
trap - EXIT
find "${INSTALL_LIB}" -maxdepth 1 -type f -name '*.so.*' -exec chmod 644 {} +

say "registering ${INSTALL_LIB} with ldconfig"
echo "${INSTALL_LIB}" > /etc/ld.so.conf.d/blakestream-mpos.conf
ldconfig

# Sanity check
"${INSTALL_BIN}/blakecoind" --version >/dev/null
say "daemons present and link-OK"
