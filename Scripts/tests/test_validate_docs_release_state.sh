#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "$repo_root/Scripts/validate_docs_release_state.sh" --expect draft
bash "$repo_root/Scripts/validate_docs_release_state.sh" --expect draft --ref HEAD

if bash "$repo_root/Scripts/validate_docs_release_state.sh" --expect ready \
  >/dev/null 2>&1; then
  echo "docs release-state test: draft unexpectedly passed as ready" >&2
  exit 1
fi

echo "docs release-state tests: OK"
