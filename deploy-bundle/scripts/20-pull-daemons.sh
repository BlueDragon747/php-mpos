#!/usr/bin/env bash
# Pull the six configured daemon images from Docker Hub, extract
# their binaries to MPOS_INSTALL_ROOT/bin/, and install the libboost-1.74
# runtime libs that the binaries (jammy-built) need on Ubuntu 24.04
# hosts.
#
# Mirrors the Eliopool testnet stack's image-pull mode.
set -euo pipefail

say() { printf '\033[1;33m   %s\033[0m\n' "$*"; }

INSTALL_BIN="${MPOS_INSTALL_ROOT}/bin"
INSTALL_LIB="${MPOS_INSTALL_ROOT}/lib"
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
    image="sidgrip/${repo}:15.21"
    say "pulling ${image}"
    docker pull -q "${image}" >/dev/null
    cid=$(docker create "${image}")
    docker cp "${cid}:/usr/local/bin/${daemon}" "${INSTALL_BIN}/${daemon}"
    docker cp "${cid}:/usr/local/bin/${cli}"    "${INSTALL_BIN}/${cli}"
    docker cp "${cid}:/usr/local/bin/${tx}"     "${INSTALL_BIN}/${tx}"
    docker rm -f "${cid}" >/dev/null
    chmod 755 "${INSTALL_BIN}/${daemon}" "${INSTALL_BIN}/${cli}" "${INSTALL_BIN}/${tx}"
done

# libboost 1.74 — extracted from the jammy-based blakecoin image so the
# native binaries can find them on a 24.04 host.
say "extracting libboost 1.74 runtime libs"
cid=$(docker create sidgrip/blakecoin:15.21)
for lib in libboost_filesystem.so.1.74.0 libboost_program_options.so.1.74.0 \
           libboost_thread.so.1.74.0 libboost_chrono.so.1.74.0; do
    docker cp "${cid}:/usr/lib/x86_64-linux-gnu/${lib}" "${INSTALL_LIB}/${lib}"
done
docker rm -f "${cid}" >/dev/null
chmod 644 "${INSTALL_LIB}"/*.so.*

say "registering ${INSTALL_LIB} with ldconfig"
echo "${INSTALL_LIB}" > /etc/ld.so.conf.d/blakestream-mpos.conf
ldconfig

# Sanity check
"${INSTALL_BIN}/blakecoind" --version >/dev/null
say "daemons present and link-OK"
