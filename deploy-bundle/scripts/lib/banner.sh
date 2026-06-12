#!/usr/bin/env bash

print_blakestream_banner() {
    [ "${BLAKESTREAM_TOOL_BANNER:-1}" != "0" ] || return 0
    [ "${BLAKESTREAM_TOOL_BANNER_PRINTED:-0}" != "1" ] || return 0
    export BLAKESTREAM_TOOL_BANNER_PRINTED=1

    cat <<'EOF'
 ____  _       _          ____  _
| __ )| | __ _| | _____  / ___|| |_ _ __ ___  __ _ _ __ ___
|  _ \| |/ _` | |/ / _ \ \___ \| __| '__/ _ \/ _` | '_ ` _ \
| |_) | | (_| |   <  __/  ___) | |_| | |  __/ (_| | | | | | |
|____/|_|\__,_|_|\_\___| |____/ \__|_|  \___|\__,_|_| |_| |_|
EOF
}
