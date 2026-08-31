#!/usr/bin/env sh
# launchd plist guardrails — the single source for both assertions.
#
# Called from lefthook's pre-commit (staged files) and .github/workflows/lint.yml
# (every tracked plist).
#
# WHY TWO ASSERTIONS AND NOT ONE. launchd does NOT expand `~` or `$HOME` in a
# plist value. It fails the job with EX_CONFIG (78) BEFORE running it, so the
# only symptom is a job that silently never runs — and structural validity does
# not catch it, because such a plist parses cleanly. The path-value assertion is
# the one that would.
#
# plutil is macOS-only; plistlib is the portable equivalent, so this prefers
# plutil when present and falls back.
set -eu

fail=0

# An empty input list is a failure, not a pass: an empty `$(git ls-files …)`
# expansion in CI must not report success for zero files checked.
[ "$#" -gt 0 ] || {
  echo "no inputs — the caller's glob matched nothing, so no plist was checked" >&2
  exit 1
}

for f in "$@"; do
  [ -f "$f" ] || {
    echo "$f: expected plist is missing"
    fail=1
    continue
  }

  if command -v plutil > /dev/null 2>&1; then
    plutil -lint "$f" > /dev/null || {
      echo "$f: not a valid plist"
      fail=1
      continue
    }
  else
    python3 -c "import plistlib,sys; plistlib.load(open(sys.argv[1],'rb'))" "$f" || {
      echo "$f: not a valid plist"
      fail=1
      continue
    }
  fi

  if grep -nE '<string>[~$]' "$f"; then
    echo "$f: launchd does not expand ~ or \$HOME in a plist value — use an absolute path (EX_CONFIG 78, the job silently never runs)"
    fail=1
  fi
done

[ "$fail" -eq 0 ] || exit 1
echo "ok plists ($*)"
