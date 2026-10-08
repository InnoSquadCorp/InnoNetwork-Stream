#!/usr/bin/env bash
# Read-only validation; never alter the dependency checkout or its object store.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 <dependency-checkout>" >&2; exit 64; }
git -C "$1" fsck --no-reflogs --connectivity-only --no-dangling >/dev/null
