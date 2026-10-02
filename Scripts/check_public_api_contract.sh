#!/usr/bin/env bash
set -euo pipefail

dependency_arguments=()
if [[ "${1:-}" == "--development" ]]; then
  dependency_arguments=(--development)
  shift
fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--development]" >&2; exit 64; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
symbols_dir="$repo_root/Scripts/symbols"
budgets_file="$symbols_dir/budgets.tsv"
cd "$repo_root"

fail() {
  echo "public-api-contract: $1" >&2
  exit 1
}

[[ -f "$budgets_file" ]] || fail "missing Scripts/symbols/budgets.tsv"
bash Scripts/check_innonetwork_dependency.sh ${dependency_arguments[@]+"${dependency_arguments[@]}"}

# Select only this build context; never delete diagnostic or other-context graphs.
scratch_path="$(python3 Scripts/swiftpm_scratch_path.py "$repo_root")"
bash Scripts/swiftpm.sh package --force-resolved-versions dump-symbol-graph \
  --minimum-access-level public \
  --skip-synthesized-members >/dev/null

actual="$(mktemp "${TMPDIR:-/tmp}/innostream-symbols.XXXXXX")"
cleanup() {
  rm -f "$actual"
}
trap cleanup EXIT
python3 Scripts/collect_public_symbols.py . --build-root "$scratch_path" > "$actual"

declare -a contracts=(
  "InnoNetworkHLS:hls.allowlist"
  "InnoNetworkHLSLive:hls-live.allowlist"
  "InnoNetworkHLSAVFoundation:hls-avfoundation.allowlist"
  "InnoNetworkHLSAudio:hls-audio.allowlist"
)

total=0
for contract in "${contracts[@]}"; do
  module="${contract%%:*}"
  allowlist="${contract##*:}"
  expected_path="$symbols_dir/$allowlist"
  [[ -f "$expected_path" ]] || fail "missing $allowlist"

  expected="$(mktemp "${TMPDIR:-/tmp}/innostream-expected.XXXXXX")"
  observed="$(mktemp "${TMPDIR:-/tmp}/innostream-observed.XXXXXX")"
  awk 'NF && $0 !~ /^#/ { print }' "$expected_path" | LC_ALL=C sort -u > "$expected"
  awk -F '\t' -v module="$module" '$1 == module { print }' "$actual" \
    | LC_ALL=C sort -u > "$observed"

  if ! diff -u "$expected" "$observed"; then
    rm -f "$expected" "$observed"
    fail "$module symbol graph drifted; review and update $allowlist"
  fi

  count="$(wc -l < "$observed" | tr -d ' ')"
  budget="$(awk -F '\t' -v file="$allowlist" '$1 == file { print $2 }' "$budgets_file")"
  [[ "$budget" =~ ^[0-9]+$ ]] || fail "missing numeric budget for $allowlist"
  (( count <= budget )) || fail "$allowlist exports $count declarations (budget: $budget)"
  total=$((total + count))
  rm -f "$expected" "$observed"
done

total_budget="$(awk -F '\t' '$1 == "TOTAL" { print $2 }' "$budgets_file")"
[[ "$total_budget" =~ ^[0-9]+$ ]] || fail "missing numeric TOTAL budget"
(( total <= total_budget )) \
  || fail "all modules export $total declarations (budget: $total_budget)"

echo "public-api-contract: OK ($total/$total_budget)"
python3 Scripts/collect_public_signatures.py . \
  --build-root "$scratch_path" \
  --check Scripts/symbols/public-signatures.tsv
