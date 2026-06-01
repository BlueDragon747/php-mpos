#!/usr/bin/env bash
# Pull the six configured daemon images from Docker Hub, extract
# their binaries to MPOS_INSTALL_ROOT/bin/, and install the runtime libs
# that the extracted binaries need on Ubuntu 24.04 hosts.
#
# Mirrors the Eliopool testnet stack's image-pull mode.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_BIN="${MPOS_INSTALL_ROOT}/bin"
INSTALL_LIB="${MPOS_INSTALL_ROOT}/lib"
MPOS_DOCKER_HUB="${MPOS_DOCKER_HUB:-sidgrip}"
MPOS_IMAGE_TAG="${MPOS_IMAGE_TAG:-25.2}"
mkdir -p "$INSTALL_BIN" "$INSTALL_LIB"

# (image_repo, daemon, cli, tx)
COIN_TUPLES=(
    "blakecoin|blakecoind|blakecoin-cli|blakecoin-tx"
    "blakebitcoin|blakebitcoind|blakebitcoin-cli|blakebitcoin-tx"
    "electron|electrond|electron-cli|electron-tx"
    "lithium|lithiumd|lithium-cli|lithium-tx"
    "photon|photond|photon-cli|photon-tx"
    "universalmolecule|universalmoleculed|universalmolecule-cli|universalmolecule-tx"
)

for row in "${COIN_TUPLES[@]}"; do
    IFS='|' read -r repo daemon cli tx <<< "$row"
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
