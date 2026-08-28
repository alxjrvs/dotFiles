#!/usr/bin/env sh
# launchd plist guardrails — the single source for both assertions.
#
# Called from lefthook's pre-commit (staged files) and .github/workflows/lint.yml
# (every tracked plist). It was written twice, and the two copies had already
# diverged in implementation: lefthook used `plutil -lint`, CI used Python's
# plistlib. Same rule, two languages, no way to tell which was authoritative.
#
# WHY TWO ASSERTIONS AND NOT ONE. launchd does NOT expand `~` or `$HOME` in a
# plist value. It fails the job with EX_CONFIG (78) BEFORE running it, so the
# only symptom is a job that silently never runs. `com.alxjrvs.boom-verify.plist`
# reported runs=0 for 28 days for exactly this reason — while the identical bug
# had already been found and fixed in the capslock plist and not carried across.
# Structural validity does not catch it: both plists parsed cleanly the whole
# time. The path-value assertion is the one that would have.
#
# plutil is macOS-only; plistlib is the portable equivalent, so this prefers
# plutil when present and falls back. That is the divergence the two copies had,
# resolved once here rather than differently in each.
set -eu

fail=0

for f in "$@"; do
  [ -f "$f" ] || continue

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
