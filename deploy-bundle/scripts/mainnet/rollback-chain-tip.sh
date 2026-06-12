#!/usr/bin/env bash
# Compatibility wrapper. The operator-run rollback tool lives in tools/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
exec "${REPO_ROOT}/tools/chain-rollback.sh" "$@"
