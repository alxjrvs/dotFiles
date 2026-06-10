#!/usr/bin/env bash
# install/95-prune.sh — cleanup: .bak files, stale worktrees, orphan workers,
# stale cost dirs.
#
# Modes (env vars or flags when run standalone):
#   PRUNE_MODE=auto   — delete without prompting (AutoYes)
#   PRUNE_MODE=dry    — list only, never delete (DryRun)
#   default           — prompt [Y/n], default yes (AskDefaultYes)
#
# Tags: prune
# Runnable standalone: ./install/95-prune.sh [-y|--yes] [-n|--dry-run]
# Also sourced by sync (calls _prune_run directly).

set -euo pipefail

# mapfile below needs bash 4+; Apple's /bin/bash is 3.2 forever, so a fresh
# machine running this standalone must fail with a real message instead of
# aborting mid-clean (brew "bash" is in the Brewfile).
if ((BASH_VERSINFO[0] < 4)); then
  printf '95-prune: bash >= 4 required (this is %s) — brew install bash\n' \
    "${BASH_VERSION}" >&2
  # return when sourced (sync), exit when standalone.
  # shellcheck disable=SC2317
  return 1 2> /dev/null || exit 1
fi

# ── Self-contained helpers ────────────────────────────────────────────────────
if [[ -z "${__DOT_SYNC_SOURCED:-}" ]]; then
  _PRUNE_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  os_kind() {
    case "$(uname -s)" in
      Darwin) printf 'darwin\n' ;;
      Linux) printf 'linux\n' ;;
      *) printf 'unknown\n' ;;
    esac
  }
  # resolve_dotfiles_dir: $DOTFILES_DIR → script's parent dir → ~/dotFiles
  resolve_dotfiles_dir() {
    local candidates=(
      "${DOTFILES_DIR:-}"
      "${_PRUNE_SELF_DIR%/install}"
      "${HOME}/dotFiles"
    )
    local c
    for c in "${candidates[@]}"; do
      [[ -n "$c" && -d "$c" && -f "${c}/Brewfile" ]] && printf '%s\n' "$c" && return 0
    done
    return 1
  }
fi

_prune_tags() { printf 'prune\n'; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Prompt "Delete these X? [Y/n]", default yes on a TTY. On a non-TTY
# (cron/CI/sandboxed session) the safe answer is NO — same convention as
# link()'s non-interactive conflict skip. Returns 0=yes, 1=no.
_prune_ask_yes() {
  local question="$1"
  if [[ ! -t 0 ]]; then
    printf '\033[0;33m  \xe2\x9a\xa0 Non-interactive; skipping (run with -y to delete unattended)\033[0m\n' >&2
    return 1
  fi
  printf '       %s [Y/n]: ' "$question" >&2
  local reply
  read -r reply || reply=""
  case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')" in
    "" | y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Shared list → confirm → apply skeleton for the prune passes.
# Caller fills the parallel globals _PRUNE_ITEMS (raw values handed to ACTION)
# and _PRUNE_LABELS (display strings), then calls:
#   _prune_confirm_apply NOUN QUESTION ACTION [VERB]
# Empty item list prints a green "No NOUN" and returns. Otherwise the list is
# shown, PRUNE_MODE gates the apply (auto=yes, dry=no, ask=_prune_ask_yes),
# and ACTION <raw> runs per item: rc 0 = done, rc 2 = kept (ACTION printed its
# own reason), anything else = failed. VERB (default "Deleted") labels the
# summary line.
_prune_confirm_apply() {
  local noun="$1" question="$2" action="$3" verb="${4:-Deleted}"
  local n="${#_PRUNE_ITEMS[@]}"

  if [[ "$n" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No %s\033[0m\n' "$noun"
    return 0
  fi

  printf '\033[0;33m  Found %d %s:\033[0m\n' "$n" "$noun"
  local i
  for ((i = 0; i < n; i++)); do
    printf '\033[2m    - %s\033[0m\n' "${_PRUNE_LABELS[$i]}"
  done

  local go=0
  case "${PRUNE_MODE:-ask}" in
    auto) go=1 ;;
    dry) go=0 ;;
    *)
      _prune_ask_yes "$question" && go=1 || go=0
      ;;
  esac
  if [[ "$go" -eq 0 ]]; then
    printf '\033[2m  - Skipped (nothing removed)\033[0m\n'
    return 0
  fi

  local applied=0 failed=0 kept=0 rc
  for ((i = 0; i < n; i++)); do
    rc=0
    "$action" "${_PRUNE_ITEMS[$i]}" || rc=$?
    case "$rc" in
      0) applied=$((applied + 1)) ;;
      2) kept=$((kept + 1)) ;;
      *)
        printf '\033[0;33m  \xe2\x86\x92 failed: %s\033[0m\n' "${_PRUNE_LABELS[$i]}" >&2
        failed=$((failed + 1))
        ;;
    esac
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 %s %d %s\033[0m\n' "$verb" "$applied" "$noun"
  else
    printf '\033[0;33m  \xe2\x86\x92 %s %d, %d failed\033[0m\n' "$verb" "$applied" "$failed"
  fi
  if [[ "$kept" -gt 0 ]]; then
    printf '\033[0;33m  \xe2\x9a\xa0 Kept %d (see reasons above)\033[0m\n' "$kept"
  fi
}

# True for a YYYY-MM-DD directory name (10 chars, dashes at 4+7, digits elsewhere).
_is_date_dir() {
  local name="$1"
  [[ "${#name}" -eq 10 ]] || return 1
  [[ "${name:4:1}" == "-" && "${name:7:1}" == "-" ]] || return 1
  local i c
  for i in 0 1 2 3 5 6 8 9; do
    c="${name:$i:1}"
    [[ "$c" =~ ^[0-9]$ ]] || return 1
  done
  return 0
}

# True for a backup filename.
_is_backup_file() {
  local name
  name=$(basename "$1")
  # *.bak
  [[ "$name" == *.bak ]] && return 0
  # *.bak-<something> (non-empty suffix)
  if [[ "$name" == *".bak-"* ]]; then
    local after="${name##*.bak-}"
    [[ -n "$after" ]] && return 0
  fi
  # *.bak.<anything>
  [[ "$name" == *".bak."* ]] && return 0
  return 1
}

# Compute the non-.bak "live" sibling path for a backup file. link() creates
# backups as "${dst}.bak", so for "foo.bak" the sibling is "foo". For the
# ".bak-<suffix>" / ".bak.<suffix>" variants we strip from the ".bak" marker.
# Echoes the sibling path; empty if none can be derived.
_prune_bak_sibling() {
  local path="$1" name dir base
  dir=$(dirname "$path")
  name=$(basename "$path")
  if [[ "$name" == *.bak ]]; then
    base="${name%.bak}"
  elif [[ "$name" == *".bak-"* || "$name" == *".bak."* ]]; then
    base="${name%%.bak*}"
  else
    return 0
  fi
  [[ -z "$base" ]] && return 0
  printf '%s/%s\n' "$dir" "$base"
}

# Resolve the dotfiles repo dir for the .bak guard. Sourced by sync →
# $DOTFILES_DIR is exported; standalone → resolve_dotfiles_dir() is defined in
# the guard block above. Cached in _PRUNE_DOTFILES_DIR. Empty if unresolvable.
_prune_dotfiles_dir() {
  if [[ -n "${_PRUNE_DOTFILES_DIR+x}" ]]; then
    printf '%s\n' "$_PRUNE_DOTFILES_DIR"
    return 0
  fi
  local resolved="${DOTFILES_DIR:-}"
  if [[ -z "$resolved" ]] && declare -f resolve_dotfiles_dir > /dev/null 2>&1; then
    resolved=$(resolve_dotfiles_dir 2> /dev/null || true)
  fi
  _PRUNE_DOTFILES_DIR="$resolved"
  printf '%s\n' "$_PRUNE_DOTFILES_DIR"
}

# Guard: a .bak is safe to delete only when its live sibling is a symlink that
# points into the dotfiles repo (i.e. link() displaced a real file we still own
# a tracked copy of). If the sibling is absent, a plain file, or a symlink
# pointing elsewhere, the .bak may be the only copy of that config — keep it.
# Returns 0 = safe to delete, 1 = should be skipped.
_prune_bak_is_safe() {
  local bak="$1"
  local sibling target df
  sibling=$(_prune_bak_sibling "$bak")
  # No derivable sibling → be conservative, keep it.
  [[ -z "$sibling" ]] && return 1
  # Sibling missing entirely → the .bak may be the only copy.
  [[ -e "$sibling" || -L "$sibling" ]] || return 1
  # Sibling must be a symlink (link() replaces conflicts with a symlink).
  [[ -L "$sibling" ]] || return 1
  target=$(readlink "$sibling" 2> /dev/null || true)
  [[ -n "$target" ]] || return 1
  # Resolve relative link targets against the sibling's directory.
  case "$target" in
    /*) ;;
    *) target="$(dirname "$sibling")/${target}" ;;
  esac
  df=$(_prune_dotfiles_dir)
  [[ -n "$df" ]] || return 1
  case "$target" in
    "$df"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Walk DIR up to DEPTH levels, calling cb (a function name) on each file.
# Skips .git, node_modules, target, share, Caches, installs, and symlinks.
_prune_walk() {
  local dir="$1" depth="$2" cb="$3"
  [[ "$depth" -le 0 ]] && return 0
  [[ -d "$dir" ]] || return 0
  local entry name
  while IFS= read -r -d '' entry; do
    name=$(basename "$entry")
    # Skip noisy subtrees.
    case "$name" in
      .git | node_modules | target | share | Caches | installs) continue ;;
    esac
    # Skip symlinks (avoid loop into mise/cargo dirs).
    [[ -L "$entry" ]] && continue
    if [[ -d "$entry" ]]; then
      _prune_walk "$entry" $((depth - 1)) "$cb"
    elif [[ -f "$entry" ]]; then
      "$cb" "$entry"
    fi
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2> /dev/null)
}

# ── Pass 1: backup files ──────────────────────────────────────────────────────

_prune_collect_backup() {
  _is_backup_file "$1" && _PRUNE_BACKUPS+=("$1") || true
}

# Action: delete one .bak, guarded — a .bak whose live sibling is NOT a
# symlink into the dotfiles repo may be the only copy of a displaced config.
_prune_rm_backup() {
  local b="$1"
  if ! _prune_bak_is_safe "$b"; then
    printf '\033[0;33m  \xe2\x9a\xa0 keeping %s (sibling not a dotfiles symlink — may be the only copy)\033[0m\n' \
      "${b/#$HOME\//~/}" >&2
    return 2
  fi
  rm -f "$b" 2> /dev/null
}

_prune_backups() {
  local home="${1:-$HOME}"
  _PRUNE_BACKUPS=()

  # Scan roots and depths for .bak backups.
  _prune_walk "$home" 1 _prune_collect_backup
  _prune_walk "${home}/.config" 4 _prune_collect_backup
  _prune_walk "${home}/.claude" 4 _prune_collect_backup
  _prune_walk "${home}/.ssh" 1 _prune_collect_backup

  printf '\n==> Backup cleanup\n'
  _PRUNE_ITEMS=() _PRUNE_LABELS=()
  local b
  for b in "${_PRUNE_BACKUPS[@]+"${_PRUNE_BACKUPS[@]}"}"; do
    _PRUNE_ITEMS+=("$b")
    _PRUNE_LABELS+=("${b/#$home\//~/}")
  done
  _prune_confirm_apply "backup file(s)" "Delete these backups?" _prune_rm_backup
}

# ── Pass 2: stale worktrees ───────────────────────────────────────────────────

_classify_worktree() {
  # Returns "STATE|reason|path|parent" where STATE is one of:
  #   skip   — not a git repo at all; NEVER removable (stray data, not a
  #            stale worktree — "git fails entirely" must not read as clean)
  #   active — parent repo still lists this worktree
  #   dirty  — uncommitted changes; listed but never auto-removed
  #   clean  — genuinely stale and safe to offer for removal
  local wt_path="$1"
  if ! git -C "$wt_path" rev-parse --git-dir > /dev/null 2>&1; then
    printf 'skip|not_git|%s|\n' "$wt_path"
    return 0
  fi
  local dirty=0
  if git -C "$wt_path" status --porcelain 2> /dev/null | grep -q .; then
    dirty=1
  fi

  local common_dir
  common_dir=$(git -C "$wt_path" rev-parse --git-common-dir 2> /dev/null || true)
  if [[ -z "$common_dir" ]]; then
    # git rev-parse failed → parent gone.
    printf '%s|parent_gone|%s|\n' "$([ "$dirty" -eq 1 ] && echo dirty || echo clean)" "$wt_path"
    return 0
  fi

  local parent_repo
  parent_repo=$(dirname "$common_dir")
  if [[ ! -d "$parent_repo" ]]; then
    printf '%s|parent_gone|%s|\n' "$([ "$dirty" -eq 1 ] && echo dirty || echo clean)" "$wt_path"
    return 0
  fi

  # Ask parent whether it knows this worktree.
  local wt_real parent_list
  wt_real=$(cd "$wt_path" && pwd -P 2> /dev/null || printf '%s' "$wt_path")
  parent_list=$(git -C "$parent_repo" worktree list --porcelain 2> /dev/null || true)
  local found=0
  local line listed_real
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      local listed="${line#worktree }"
      listed_real=$(cd "$listed" && pwd -P 2> /dev/null || true)
      if [[ "$listed_real" == "$wt_real" ]]; then
        found=1
        break
      fi
    fi
  done <<< "$parent_list"

  if [[ "$found" -eq 1 ]]; then
    printf 'active||%s|%s\n' "$wt_path" "$parent_repo"
  else
    printf '%s|not_in_parent|%s|%s\n' \
      "$([ "$dirty" -eq 1 ] && echo dirty || echo clean)" \
      "$wt_path" "$parent_repo"
  fi
}

_prune_stale_worktrees() {
  local home="${1:-$HOME}"
  printf '\n==> Stale worktree cleanup\n'

  local root="${home}/.local/share/cc-worktrees"
  if [[ ! -d "$root" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale worktrees\033[0m\n'
    return 0
  fi

  local -a dirty_list=() skip_list=()
  local repo_dir wt_dir result state reason parent
  _PRUNE_ITEMS=() _PRUNE_LABELS=()

  for repo_dir in "$root"/*/; do
    [[ -d "$repo_dir" ]] || continue
    for wt_dir in "$repo_dir"*/; do
      [[ -d "$wt_dir" ]] || continue
      wt_dir="${wt_dir%/}"
      result=$(_classify_worktree "$wt_dir" 2> /dev/null || printf 'active||%s|\n' "$wt_dir")
      IFS='|' read -r state reason _ parent <<< "$result"
      case "$state" in
        active) continue ;;
        skip) skip_list+=("$wt_dir") ;;
        dirty) dirty_list+=("$wt_dir") ;;
        *)
          local reason_str
          case "$reason" in
            parent_gone) reason_str="parent gone" ;;
            not_in_parent) reason_str="not in parent list" ;;
            *) reason_str="$reason" ;;
          esac
          _PRUNE_ITEMS+=("$wt_dir|$parent")
          _PRUNE_LABELS+=("${wt_dir/#$home\//~/}  [$reason_str]")
          ;;
      esac
    done
  done

  if [[ "${#skip_list[@]}" -gt 0 ]]; then
    printf '\033[0;33m  Found %d non-git dir(s) under the worktree root (skipping):\033[0m\n' "${#skip_list[@]}"
    local entry
    for entry in "${skip_list[@]}"; do
      printf '\033[2m    - %s  [not a git repo — inspect manually]\033[0m\n' "${entry/#$home\//~/}"
    done
  fi

  if [[ "${#dirty_list[@]}" -gt 0 ]]; then
    printf '\033[0;33m  Found %d stale worktree(s) with UNCOMMITTED changes (skipping):\033[0m\n' "${#dirty_list[@]}"
    local entry
    for entry in "${dirty_list[@]}"; do
      printf '\033[2m    - %s  [DIRTY — inspect manually]\033[0m\n' "${entry/#$home\//~/}"
    done
  fi

  _prune_confirm_apply "stale worktree(s)" "Remove these worktrees?" _prune_rm_worktree Removed
}

# Action: remove one stale worktree. Raw item is "wt_path|parent_path".
_prune_rm_worktree() {
  local wt_path parent_path
  IFS='|' read -r wt_path parent_path <<< "$1"
  if [[ -n "$parent_path" && -d "$parent_path" ]]; then
    git -C "$parent_path" worktree remove --force "$wt_path" \
      > /dev/null 2>&1 || true
    git -C "$parent_path" worktree prune \
      > /dev/null 2>&1 || true
  fi
  if [[ -d "$wt_path" ]]; then
    rm -rf "$wt_path" 2> /dev/null || return 1
  fi
  return 0
}

# ── Pass 3: orphan bg-spare workers ──────────────────────────────────────────

_get_process_cwd() {
  local pid="$1"
  lsof -a -p "$pid" -d cwd -F n 2> /dev/null |
    awk '/^n/ { print substr($0,2); exit }'
}

_ancestor_pids() {
  local cur="$1" i
  for i in $(seq 1 16); do
    local ppid
    ppid=$(ps -o ppid= -p "$cur" 2> /dev/null | tr -d ' ') || break
    [[ "$ppid" =~ ^[0-9]+$ ]] || break
    [[ "$ppid" -le 1 ]] && break
    printf '%s\n' "$ppid"
    cur="$ppid"
  done
}

_prune_orphan_workers() {
  printf '\n==> Orphan worker cleanup\n'

  local -a spare_pids=()
  local pid
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && spare_pids+=("$pid")
  done < <(pgrep -f 'claude.*--bg-spare' 2> /dev/null || true)

  if [[ "${#spare_pids[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No orphan workers\033[0m\n'
    return 0
  fi

  local self_pid=$$
  local -a ancestors=()
  while IFS= read -r pid; do
    ancestors+=("$pid")
  done < <(_ancestor_pids "$self_pid")

  local -a orphans=()
  local p cwd skip
  for p in "${spare_pids[@]}"; do
    skip=0
    [[ "$p" -eq "$self_pid" ]] && skip=1
    local anc
    for anc in "${ancestors[@]+"${ancestors[@]}"}"; do
      [[ "$p" -eq "$anc" ]] && skip=1 && break
    done
    [[ "$skip" -eq 1 ]] && continue

    cwd=$(_get_process_cwd "$p" 2> /dev/null || true)
    if [[ -n "$cwd" && ! -d "$cwd" ]]; then
      orphans+=("$p|$cwd")
    fi
  done

  _PRUNE_ITEMS=() _PRUNE_LABELS=()
  local o
  for o in "${orphans[@]+"${orphans[@]}"}"; do
    IFS='|' read -r p cwd <<< "$o"
    _PRUNE_ITEMS+=("$p")
    _PRUNE_LABELS+=("PID $p -> $cwd")
  done
  _prune_confirm_apply "orphan worker(s)" "Kill these orphan workers?" _prune_kill_worker Killed
}

# Action: kill one orphan worker by pid.
_prune_kill_worker() {
  kill "$1" 2> /dev/null
}

# ── Pass 4: stale daily-cost dirs ─────────────────────────────────────────────

_prune_stale_cost_dirs() {
  local home="${1:-$HOME}"
  printf '\n==> Stale daily-cost dirs\n'

  local root="${home}/.claude/state/cost"
  local today
  today=$(date +%Y-%m-%d)

  if [[ ! -d "$root" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale cost dirs\033[0m\n'
    return 0
  fi

  local -a stale=()
  local entry name
  while IFS= read -r -d '' entry; do
    [[ -d "$entry" ]] || continue
    name=$(basename "$entry")
    if _is_date_dir "$name" && [[ "$name" < "$today" ]]; then
      stale+=("$entry")
    fi
  done < <(find "$root" -maxdepth 1 -mindepth 1 -print0 2> /dev/null)
  # Sort for deterministic output.
  if [[ "${#stale[@]}" -gt 0 ]]; then
    mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
  fi

  _PRUNE_ITEMS=("${stale[@]+"${stale[@]}"}")
  _PRUNE_LABELS=("${stale[@]+"${stale[@]}"}")
  _prune_confirm_apply "stale cost dir(s)" "Delete these cost dirs?" _prune_rm_rf
}

# Action: rm -rf one path (cost dirs, spills).
_prune_rm_rf() {
  rm -rf "$1" 2> /dev/null
}

# ── Pass 5: unbounded state journals ──────────────────────────────────────────

# Bound an append-only JSONL journal: if it exceeds HARD lines, truncate to the
# last KEEP lines in place (atomic via temp file). Idempotent: a file already
# under HARD is left untouched.
_prune_bound_jsonl() {
  local file="$1" keep="$2" hard="$3" home="$4"
  [[ -f "$file" ]] || return 0
  local lines
  lines=$(wc -l < "$file" 2> /dev/null | tr -d ' ')
  [[ "$lines" =~ ^[0-9]+$ ]] || return 0

  local display="${file/#$home\//~/}"
  if [[ "$lines" -le "$hard" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 %s (%d lines, within bound)\033[0m\n' "$display" "$lines"
    return 0
  fi

  printf '\033[0;33m  %s has %d lines (> %d); will trim to last %d\033[0m\n' \
    "$display" "$lines" "$hard" "$keep"

  local do_trim=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_trim=1 ;;
    dry) do_trim=0 ;;
    *)
      _prune_ask_yes "Trim ${display}?" && do_trim=1 || do_trim=0
      ;;
  esac

  if [[ "$do_trim" -eq 0 ]]; then
    printf '\033[2m  - Skipped (left unbounded)\033[0m\n'
    return 0
  fi

  local tmp="${file}.prune.$$"
  if tail -n "$keep" "$file" > "$tmp" 2> /dev/null && mv "$tmp" "$file" 2> /dev/null; then
    printf '\033[0;32m  \xe2\x9c\x93 Trimmed %s to %d lines\033[0m\n' "$display" "$keep"
  else
    rm -f "$tmp" 2> /dev/null || true
    printf '\033[0;33m  \xe2\x86\x92 failed to trim %s\033[0m\n' "$display" >&2
  fi
}

_prune_state_journals() {
  local home="${1:-$HOME}"
  printf '\n==> State journal bounding\n'
  # Keep the last 500 entries once a journal grows past ~1000 lines.
  _prune_bound_jsonl "${home}/.claude/state/hook-timings.jsonl" 500 1000 "$home"
  # P3 ledgers — same line-bound treatment as hook-timings.jsonl.
  _prune_bound_jsonl "${home}/.claude/state/precompact-snapshots.jsonl" 500 1000 "$home"
  _prune_bound_jsonl "${home}/.claude/state/subagent-ledger.jsonl" 500 1000 "$home"
}

# ── Pass 5b: stale per-session shards ─────────────────────────────────────────
# hooks/stop now writes per-session shards under state/sessions/<id>.jsonl
# (replacing the single sessions.jsonl). Age them out the same way as cost dirs
# / spills: a shard last modified before midnight today is stale.
_prune_session_shards() {
  local home="${1:-$HOME}"
  printf '\n==> Stale session shards\n'

  local root="${home}/.claude/state/sessions"
  if [[ ! -d "$root" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale session shards\033[0m\n'
    return 0
  fi

  local today
  today=$(date +%Y-%m-%d)

  local -a stale=()
  local entry mday
  while IFS= read -r -d '' entry; do
    [[ -f "$entry" ]] || continue
    mday=$(date -r "$entry" +%Y-%m-%d 2> /dev/null || true)
    [[ -n "$mday" && "$mday" < "$today" ]] && stale+=("$entry")
  done < <(find "$root" -maxdepth 1 -mindepth 1 -name '*.jsonl' -print0 2> /dev/null)

  if [[ "${#stale[@]}" -gt 0 ]]; then
    mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
  fi

  _PRUNE_ITEMS=() _PRUNE_LABELS=()
  local d
  for d in "${stale[@]+"${stale[@]}"}"; do
    _PRUNE_ITEMS+=("$d")
    _PRUNE_LABELS+=("${d/#$home\//~/}")
  done
  _prune_confirm_apply "stale session shard(s)" "Delete these session shards?" _prune_rm_f
}

# Action: rm -f one file (session shards, journals).
_prune_rm_f() {
  rm -f "$1" 2> /dev/null
}

# ── Pass 6: stale bash-output spills ──────────────────────────────────────────

_prune_stale_spills() {
  printf '\n==> Stale bash-output spills\n'

  local -a roots=("/tmp/claude/spills" "/private/tmp/claude/spills")
  local -a stale=()
  local root entry display
  # Match the cost-dir convention: an entry is stale once its date precedes
  # today. Spill files carry no date in their name, so use mtime: anything
  # last modified before midnight today (older than today) is stale.
  local today
  today=$(date +%Y-%m-%d)
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' entry; do
      local mday
      mday=$(date -r "$entry" +%Y-%m-%d 2> /dev/null || true)
      [[ -n "$mday" && "$mday" < "$today" ]] && stale+=("$entry")
    done < <(find "$root" -mindepth 1 -print0 2> /dev/null)
  done

  if [[ "${#stale[@]}" -gt 0 ]]; then
    mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
  fi

  _PRUNE_ITEMS=("${stale[@]+"${stale[@]}"}")
  _PRUNE_LABELS=("${stale[@]+"${stale[@]}"}")
  _prune_confirm_apply "stale spill(s)" "Delete these spills?" _prune_rm_rf
}

# ── Main entry ────────────────────────────────────────────────────────────────

_prune_run() {
  _prune_backups "${HOME}"
  _prune_stale_worktrees "${HOME}"
  _prune_orphan_workers
  _prune_stale_cost_dirs "${HOME}"
  _prune_state_journals "${HOME}"
  _prune_session_shards "${HOME}"
  _prune_stale_spills
}

# ── Standalone execution (dot prune / ./install/95-prune.sh) ─────────────────
# When run directly (not sourced), parse flags and invoke _prune_run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  for _prune_arg in "$@"; do
    case "$_prune_arg" in
      -y | --yes) PRUNE_MODE="auto" ;;
      -n | --dry-run) PRUNE_MODE="dry" ;;
    esac
  done
  unset _prune_arg
  export PRUNE_MODE="${PRUNE_MODE:-ask}"
  _prune_run
fi
