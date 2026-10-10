#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected=""
git_ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect) [[ $# -ge 2 ]] || exit 64; expected="$2"; shift 2 ;;
    --ref) [[ $# -ge 2 ]] || exit 64; git_ref="$2"; shift 2 ;;
    *) echo 'Usage: validate_docs_release_state.sh [--expect draft|ready] [--ref commit]' >&2; exit 64 ;;
  esac
done
case "$expected" in ''|draft|ready) ;; *) exit 64 ;; esac
fail() { echo "docs-release-state: $1" >&2; exit 1; }
if [[ -n "$git_ref" ]]; then
  resolved_ref="$(git -C "$repo_root" rev-parse --verify "${git_ref}^{commit}")"
  version="$(git -C "$repo_root" show "$resolved_ref:RELEASE_VERSION")"
else
  version="$(cat "$repo_root/RELEASE_VERSION")"
fi
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'invalid RELEASE_VERSION'
major="${version%%.*}"
required_paths=(RELEASE_VERSION "docs/releases/$version.md" docs/ROADMAP.md API_STABILITY.md README.md CHANGELOG.md SECURITY.md)
validation_root="$repo_root"
temporary_root=""
cleanup() { [[ -z "$temporary_root" ]] || rm -rf "$temporary_root"; }
trap cleanup EXIT
if [[ -n "$git_ref" ]]; then
  temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/innostream-release-state.XXXXXX")"
  validation_root="$temporary_root"
  for path in "${required_paths[@]}"; do
    [[ "$(git -C "$repo_root" cat-file -t "$resolved_ref:$path" 2>/dev/null || true)" == blob ]] || fail "missing $path"
    mkdir -p "$validation_root/$(dirname "$path")"
    git -C "$repo_root" cat-file blob "$resolved_ref:$path" > "$validation_root/$path"
  done
fi
for path in "${required_paths[@]}"; do [[ -f "$validation_root/$path" ]] || fail "missing $path"; done
notes="$validation_root/docs/releases/$version.md"
api="$validation_root/API_STABILITY.md"
readme="$validation_root/README.md"
changelog="$validation_root/CHANGELOG.md"
security="$validation_root/SECURITY.md"
roadmap="$validation_root/docs/ROADMAP.md"
grep -Fqx '## Release Boundary' "$roadmap"
grep -Fqx '## Follow-up Scope' "$roadmap"
grep -Fq '[Roadmap](docs/ROADMAP.md)' "$readme"
[[ "$(grep -Ec '<!-- release-status: (draft|ready) -->' "$notes")" == 1 ]] || fail 'one status marker required'
[[ "$(grep -c '^Status:' "$notes")" == 1 ]] || fail 'one status field required'
[[ "$(grep -c '^Release date:' "$notes")" == 1 ]] || fail 'one release date required'
case "$(sed -n '1p' "$notes")" in
  '<!-- release-status: draft -->') state=draft ;;
  '<!-- release-status: ready -->') state=ready ;;
  *) fail 'status marker must be first line' ;;
esac
[[ -z "$expected" || "$state" == "$expected" ]] || fail "expected $expected, found $state"
if [[ "$state" == draft ]]; then
  grep -Fqx 'Status: Release candidate (unpublished)' "$notes"
  grep -Fqx 'Release date: Not scheduled' "$notes"
  grep -Fqx "# API Stability ($major.x candidate)" "$api"
  grep -Fq "\`$version\` is an unpublished release candidate." "$readme"
  if grep -Eq "^## \\[$version\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog"; then
    fail 'candidate changelog must not claim a dated release'
  fi
else
  grep -Fqx 'Status: Ready for release' "$notes"
  release_date="$(sed -nE 's/^Release date: ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$notes")"
  [[ -n "$release_date" ]] || fail 'ready notes require release date'
  python3 -c 'import datetime,sys; datetime.date.fromisoformat(sys.argv[1])' "$release_date"
  grep -Fqx "# API Stability ($major.x)" "$api"
  # Preserve historical Ready release notes after the tag is published.
  # A published quick start must identify the exact version and release URL.
  if ! grep -Fq "\`$version\` is ready for publication." "$readme"; then
    grep -Fq "\`$version\` is published." "$readme"
    grep -Eo 'https://[^[:space:])>]+' "$readme" \
      | grep -Fxq "https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/$version"
  fi
  grep -Fqx "## [$version] - $release_date" "$changelog"
  grep -Fiq "the latest \`$major.x\` minor is the actively supported line." "$security"
fi
echo "docs-release-state: OK ($version $state${git_ref:+ at $git_ref})"
