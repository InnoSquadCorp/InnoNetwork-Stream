#!/usr/bin/env bash
# Supported local/CI entry point: preserve the old .build tree after a rename.
set -euo pipefail
script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in build|test|package|run) ;; *) echo "Usage: bash Scripts/swiftpm.sh <build|test|package|run> [SwiftPM options]" >&2; exit 64 ;; esac
package_root="$(pwd -P)"
scratch_base=""
sdk_path=""
arguments=("$1")
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-path)
      [[ $# -ge 2 ]] || exit 64
      package_root="$2"; arguments+=("$1" "$2"); shift 2 ;;
    --package-path=*) package_root="${1#*=}"; arguments+=("$1"); shift ;;
    --scratch-path)
      [[ $# -ge 2 ]] || exit 64
      scratch_base="$2"; shift 2 ;;
    --scratch-path=*) scratch_base="${1#*=}"; shift ;;
    --sdk)
      [[ $# -ge 2 ]] || exit 64
      sdk_path="$2"; arguments+=("$1" "$2"); shift 2 ;;
    --sdk=*) sdk_path="${1#*=}"; arguments+=("$1"); shift ;;
    --) arguments+=("$@"); break ;;
    *) arguments+=("$1"); shift ;;
  esac
done
resolver=("$package_root")
[[ -z "$scratch_base" ]] || resolver+=(--base "$scratch_base")
[[ -z "$sdk_path" ]] || resolver+=(--sdk "$sdk_path")
scratch_path="$(python3 "$script_root/swiftpm_scratch_path.py" "${resolver[@]}")"
# Global options must precede package/run subcommands and executable arguments.
exec xcrun swift "${arguments[0]}" --scratch-path "$scratch_path" "${arguments[@]:1}"
