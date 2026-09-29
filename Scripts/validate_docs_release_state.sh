#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected=""
git_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect)
      [[ $# -ge 2 ]] || { echo "docs-release-state: --expect requires a value" >&2; exit 64; }
      expected="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || { echo "docs-release-state: --ref requires a commit-ish" >&2; exit 64; }
      git_ref="$2"
      shift 2
      ;;
    *)
      echo "Usage: bash Scripts/validate_docs_release_state.sh [--expect draft|ready] [--ref <commit-ish>]" >&2
      exit 64
      ;;
  esac
done

case "$expected" in
  ""|draft|ready) ;;
  *)
    echo "docs-release-state: expected state must be draft or ready" >&2
    exit 64
    ;;
esac

required_paths=(
  docs/releases/1.0.0.md
  docs/ROADMAP.md
  API_STABILITY.md
  README.md
  CHANGELOG.md
  SECURITY.md
)

validation_root="$repo_root"
temporary_root=""
cleanup() {
  if [[ -n "$temporary_root" ]]; then
    rm -rf "$temporary_root"
  fi
}
trap cleanup EXIT

if [[ -n "$git_ref" ]]; then
  resolved_ref="$(git -C "$repo_root" rev-parse --verify "${git_ref}^{commit}" 2>/dev/null || true)"
  [[ -n "$resolved_ref" ]] \
    || { echo "docs-release-state: ref '$git_ref' does not resolve to a commit" >&2; exit 1; }
  temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/innostream-release-state.XXXXXX")"
  validation_root="$temporary_root"
  for path in "${required_paths[@]}"; do
    [[ "$(git -C "$repo_root" cat-file -t "${resolved_ref}:${path}" 2>/dev/null || true)" == "blob" ]] \
      || { echo "docs-release-state: missing $path in $git_ref" >&2; exit 1; }
    mkdir -p "$(dirname "$validation_root/$path")"
    git -C "$repo_root" cat-file blob "${resolved_ref}:${path}" > "$validation_root/$path"
  done
fi

notes="$validation_root/docs/releases/1.0.0.md"
api="$validation_root/API_STABILITY.md"
readme="$validation_root/README.md"
changelog="$validation_root/CHANGELOG.md"
security="$validation_root/SECURITY.md"
roadmap="$validation_root/docs/ROADMAP.md"

for path in "$notes" "$api" "$readme" "$changelog" "$security" "$roadmap"; do
  [[ -f "$path" ]] || { echo "docs-release-state: missing ${path#"$validation_root/"}" >&2; exit 1; }
done

grep -Fqx '## 1.0.0 Release Boundary' "$roadmap"
grep -Fqx '## 1.1.0 Candidate Scope' "$roadmap"
grep -Fq '[Roadmap](docs/ROADMAP.md)' "$readme"
grep -Fq 'No 1.1 candidate below is a blocker for 1.0.' "$roadmap"

marker_count="$(grep -Ec '<!-- release-status: (draft|ready) -->' "$notes")"
[[ "$marker_count" == "1" ]] \
  || { echo "docs-release-state: release notes require exactly one status marker" >&2; exit 1; }

first_line="$(sed -n '1p' "$notes")"
case "$first_line" in
  '<!-- release-status: draft -->') state="draft" ;;
  '<!-- release-status: ready -->') state="ready" ;;
  *)
    echo "docs-release-state: status marker must be the first line" >&2
    exit 1
    ;;
esac

[[ -z "$expected" || "$state" == "$expected" ]] \
  || { echo "docs-release-state: expected $expected, found $state" >&2; exit 1; }

if [[ "$state" == "draft" ]]; then
  grep -Fqx 'Status: Draft (unreleased)' "$notes"
  grep -Fqx 'Release date: TBD' "$notes"
  grep -Fq '# API Stability (1.0 Draft)' "$api"
  grep -Fq '`1.0.0` is currently an unreleased draft.' "$readme"
  grep -Fq 'These changes have not been tagged.' "$changelog"
  grep -Eq 'No stable (InnoStream|InnoNetwork-Stream) tag exists yet\.' "$security"
  if grep -Eq '^## \[1\.0\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$changelog"; then
    echo "docs-release-state: draft changelog must not claim a 1.0.0 release" >&2
    exit 1
  fi
else
  grep -Fqx 'Status: Ready for release' "$notes"
  release_date="$(sed -nE 's/^Release date: ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$notes")"
  [[ -n "$release_date" ]] \
    || { echo "docs-release-state: ready notes require a release date" >&2; exit 1; }
  grep -Fq '# API Stability (1.x)' "$api"
  grep -Fq '`1.0.0` is the latest tagged stable release.' "$readme"
  grep -Fqx "## [1.0.0] - $release_date" "$changelog"
  grep -Fq 'The latest `1.x` minor is the actively supported line.' "$security"
  if grep -Fq 'Release date: TBD' "$notes"; then
    echo "docs-release-state: ready notes still contain a draft date" >&2
    exit 1
  fi
fi

echo "docs-release-state: OK ($state${git_ref:+ at $git_ref})"
