#!/usr/bin/env bash
# Claude Code SessionStart/SubagentStart hook — starts an agent on CURRENT code.
#
# THE BUG THIS EXISTS FOR. `worktree.baseRef: "fresh"` promises a worktree cut
# from `origin/<default>`, and the docs say exactly that. What the client
# actually does (measured against 2.1.237, decompiled and then reproduced
# end-to-end) is cut from the *local remote-tracking ref* and only refresh it
# when `.git/FETCH_HEAD` is more than 24h old:
#
#     let E = await stat(join(gitdir,"FETCH_HEAD")).then(c=>c.mtimeMs, ()=>0)
#     if (Date.now() - E > 86400000) { git fetch origin <default> }
#
# So `origin/main` can be a day stale and every agent spawned in that window
# silently branches from it. Reproduced hermetically: with FETCH_HEAD freshly
# touched, `claude --worktree` based the tree on the stale commit; with
# FETCH_HEAD aged past 24h the same command fetched and based it on the real
# tip. Both directions in tests/freshness.sh, because a suite that only asserts
# the good case cannot tell enforcement from a no-op.
#
# Worse, ANY fetch touches FETCH_HEAD — so a `git fetch origin some-branch` for
# unrelated reasons re-arms the 24h skip while leaving `origin/<default>` exactly
# as stale as it was. The gate is a cache with no invalidation.
#
# TWO LAYERS, because neither alone covers every way an agent gets spawned.
#
#   PREFETCH (session starts in the primary checkout) — refresh
#     `origin/<default>` in the background. All worktrees of a clone share one
#     object store and one set of remote-tracking refs, so this is a repo-level
#     property: keep the ref honest and the client's 24h skip becomes harmless,
#     because the ref it decides to trust is genuinely current. This fixes the
#     base AT CREATION, which is the only place it can be fixed for free.
#     Backgrounded so it never delays session start, which means it RACES a
#     dispatch that happens immediately — hence the second layer.
#
#   ENFORCE (session starts inside a linked worktree) — fetch synchronously and
#     fast-forward the branch onto its intended base. This is the backstop that
#     does not care how the agent was spawned or whether the prefetch won its
#     race, and it is the layer that actually holds.
#
# SAFETY. ENFORCE only ever runs `git merge --ff-only`, and only when HEAD is
# already an ancestor of the target — so it is arithmetically incapable of
# discarding a commit. A fresh agent worktree is created with `--no-track -B` at
# the base commit, so it is a virgin branch and the fast-forward is exactly the
# "start from current code" the agent wanted. A worktree with real work on it
# fails the ancestor test and gets a one-line advisory instead, which pairs with
# rebase-guard.sh: that guard blocks a stale PUSH, this one prevents the stale
# START that makes the push stale in the first place.
#
# FAILS OPEN, always. Offline, no remote, detached HEAD, dirty tree, missing jq,
# a fetch that times out — every one of them exits 0 and changes nothing. A hook
# that runs before the agent can say a word must never be able to wedge it.
set -u

quiet() { exit 0; }

payload=$(cat 2> /dev/null) || payload=''

# cwd from the payload, not $PWD: the two agree today, but the payload is the
# documented contract and $PWD is an implementation detail of how the client
# spawns hooks.
if command -v jq > /dev/null 2>&1; then
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2> /dev/null)
  event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2> /dev/null)
fi
[ -n "${cwd:-}" ] || cwd=$PWD
[ -n "${event:-}" ] || event=SessionStart

cd "$cwd" 2> /dev/null || quiet
git rev-parse --git-dir > /dev/null 2>&1 || quiet
git remote get-url origin > /dev/null 2>&1 || quiet

# `timeout` is not on a stock macOS; treat its absence as "run unbounded" rather
# than as a reason to skip the work.
if command -v timeout > /dev/null 2>&1; then
  bound() { timeout "$@"; }
else
  bound() {
    shift
    "$@"
  }
fi

# The default branch as the LOCAL clone understands it. Deliberately no
# `git remote show origin` fallback — that is a network round-trip on the
# critical path of every session start, to answer a question the refs already
# answer 99% of the time.
default_branch() {
  local d
  d=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2> /dev/null) &&
    [ -n "$d" ] && {
    printf '%s' "${d#origin/}"
    return 0
  }
  for d in main master; do
    git show-ref --verify --quiet "refs/remotes/origin/$d" && {
      printf '%s' "$d"
      return 0
    }
  done
  return 1
}

# --- PREFETCH ---------------------------------------------------------------
# A linked worktree has its own git dir under <common>/worktrees/<name>; the
# primary checkout has git-dir == git-common-dir. Anything that is not a linked
# worktree is the user's real checkout: never touch its working tree, only its
# refs.
#
# BOTH sides are resolved the same way, with `pwd -P`, and that symmetry is the
# whole correctness argument. The obvious spelling — `--absolute-git-dir` against
# a `cd`-ed `--git-common-dir` — compares a symlink-resolved path to a logical
# one, so on macOS (where $TMPDIR is /var/folders → /private/var/folders) the two
# never matched and the PRIMARY CHECKOUT was misread as a linked worktree and
# fast-forwarded. Caught by tests/freshness.sh `skip_primary`, which is why that
# case asserts on the user's own clone rather than only on worktrees.
gd=$(cd "$(git rev-parse --git-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet
gcd=$(cd "$(git rev-parse --git-common-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet

if [ "$gd" = "$gcd" ]; then
  base=$(default_branch) || quiet
  # Detached and backgrounded: this is an optimisation, not a gate, and it must
  # be invisible in session-start latency. git only writes FETCH_HEAD on success,
  # so a fetch that fails leaves the client's own 24h timer armed rather than
  # silently disarming it — the failure mode degrades to today's behaviour.
  (bound 30 git fetch --quiet --prune origin \
    "+refs/heads/$base:refs/remotes/origin/$base" > /dev/null 2>&1 &) &
  quiet
fi

# --- ENFORCE ----------------------------------------------------------------
branch=$(git symbolic-ref --short -q HEAD 2> /dev/null) || quiet
[ -n "$branch" ] || quiet

# Prefer the branch's own upstream when it has one — a resumed or explicitly
# tracked branch has already declared what "latest" means for it, and silently
# retargeting that at origin/<default> would be the opposite of respecting it.
# A fresh agent worktree is created `--no-track`, so it has none and falls to
# the default branch, which is the case this hook is really for.
remote=$(git config --get "branch.$branch.remote" 2> /dev/null || true)
merge_ref=$(git config --get "branch.$branch.merge" 2> /dev/null || true)
if [ -n "$remote" ] && [ -n "$merge_ref" ]; then
  target="refs/remotes/$remote/${merge_ref#refs/heads/}"
else
  base=$(default_branch) || quiet
  remote=origin
  merge_ref="refs/heads/$base"
  target="refs/remotes/origin/$base"
fi

# Synchronous, and bounded so an unreachable remote costs 15s once rather than
# hanging the session. Explicit refspec rather than `git fetch origin <branch>`:
# the bare form updates the remote-tracking ref only opportunistically, and this
# hook's entire job is that the ref is right.
bound 15 git fetch --quiet "$remote" \
  "+$merge_ref:$target" > /dev/null 2>&1 || quiet

head_sha=$(git rev-parse -q --verify HEAD 2> /dev/null) || quiet
target_sha=$(git rev-parse -q --verify "$target" 2> /dev/null) || quiet
[ "$head_sha" != "$target_sha" ] || quiet

short_target=${target#refs/remotes/}
behind=$(git rev-list --count "$head_sha..$target_sha" 2> /dev/null || echo 0)

emit() {
  command -v jq > /dev/null 2>&1 || exit 0
  jq -nc --arg e "$event" --arg c "$1" \
    '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}' 2> /dev/null
  exit 0
}

# Not a fast-forward: the branch carries commits of its own. Say so and stop —
# rebasing someone else's in-flight work from a startup hook is exactly the kind
# of unrequested history rewrite that makes a tool untrustworthy.
if ! git merge-base --is-ancestor "$head_sha" "$target_sha" 2> /dev/null; then
  ahead=$(git rev-list --count "$target_sha..$head_sha" 2> /dev/null || echo 0)
  [ "$behind" -gt 0 ] || quiet
  emit "This worktree's branch \`$branch\` has diverged from \`$short_target\`: $ahead commit(s) of its own, $behind behind. Its base is stale. Rebase onto \`$short_target\` before building on it — the rebase-before-push guard will block the push otherwise."
fi

# Tracked-file changes only: a fresh worktree's untracked build output is not a
# reason to leave it on stale code, and `git merge --ff-only` refuses on its own
# if the update would actually clobber an untracked file.
if [ -n "$(git --no-optional-locks status --porcelain --untracked-files=no 2> /dev/null)" ]; then
  emit "This worktree is $behind commit(s) behind \`$short_target\` and has uncommitted changes, so it was left alone. Its base is stale — commit or stash, then rebase onto \`$short_target\` before building on it."
fi

if git merge --ff-only --quiet "$target" > /dev/null 2>&1; then
  emit "Worktree fast-forwarded $behind commit(s) onto the current \`$short_target\` ($(git rev-parse --short HEAD)) before you started, so you are working from the latest code, not the base this worktree was cut from."
fi

emit "This worktree is $behind commit(s) behind \`$short_target\` and could not be fast-forwarded automatically. Its base is stale — rebase onto \`$short_target\` before building on it."
