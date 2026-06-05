#!/usr/bin/env bash
# install/95-prune.sh — cleanup: .bak files, stale worktrees, orphan workers,
# stale cost dirs. Ports prune.rs.
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

# Prompt "Delete these X? [Y/n]", default yes. Returns 0=yes, 1=no.
_prune_ask_yes() {
  local question="$1"
  if [[ ! -t 0 ]]; then
    printf '\033[2m  - Non-interactive; proceeding (default yes)\033[0m\n'
    return 0
  fi
  printf '       %s [Y/n]: ' "$question" >&2
  local reply
  read -r reply || reply=""
  case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')" in
    "" | y | yes) return 0 ;;
    *) return 1 ;;
  esac
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

_prune_backups() {
  local home="${1:-$HOME}"
  _PRUNE_BACKUPS=()

  # Scan roots and depths (matching prune.rs find_backups).
  _prune_walk "$home" 1 _prune_collect_backup
  _prune_walk "${home}/.config" 4 _prune_collect_backup
  _prune_walk "${home}/.claude" 4 _prune_collect_backup
  _prune_walk "${home}/.ssh" 1 _prune_collect_backup

  printf '\n==> Backup cleanup\n'
  if [[ "${#_PRUNE_BACKUPS[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No backups found\033[0m\n'
    return 0
  fi

  printf '\033[0;33m  Found %d backup file(s):\033[0m\n' "${#_PRUNE_BACKUPS[@]}"
  local b
  for b in "${_PRUNE_BACKUPS[@]}"; do
    local display="${b/#$home\//~/}"
    printf '\033[2m    - %s\033[0m\n' "$display"
  done

  local do_delete=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_delete=1 ;;
    dry) do_delete=0 ;;
    *)
      _prune_ask_yes "Delete these backups?" && do_delete=1 || do_delete=0
      ;;
  esac

  if [[ "$do_delete" -eq 0 ]]; then
    printf '\033[2m  - Skipped (no files removed)\033[0m\n'
    return 0
  fi

  local deleted=0 failed=0
  for b in "${_PRUNE_BACKUPS[@]}"; do
    if rm -f "$b" 2> /dev/null; then
      deleted=$((deleted + 1))
    else
      printf '\033[0;33m  \xe2\x86\x92 failed to delete %s\033[0m\n' "$b" >&2
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 Deleted %d backup file(s)\033[0m\n' "$deleted"
  else
    printf '\033[0;33m  \xe2\x86\x92 Deleted %d, %d failed\033[0m\n' "$deleted" "$failed"
  fi
}

# ── Pass 2: stale worktrees ───────────────────────────────────────────────────

_classify_worktree() {
  # Returns "clean|reason|path|parent" or "dirty|reason|path|parent" or "active|...|path|parent"
  local wt_path="$1"
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

  local -a removable=() dirty_list=()
  local repo_dir wt_dir result state reason wt parent

  for repo_dir in "$root"/*/; do
    [[ -d "$repo_dir" ]] || continue
    for wt_dir in "$repo_dir"*/; do
      [[ -d "$wt_dir" ]] || continue
      wt_dir="${wt_dir%/}"
      result=$(_classify_worktree "$wt_dir" 2> /dev/null || printf 'active||%s|\n' "$wt_dir")
      IFS='|' read -r state reason wt parent <<< "$result"
      if [[ "$state" == "active" ]]; then
        continue
      elif [[ "$state" == "dirty" ]]; then
        dirty_list+=("$wt_dir|$reason|$parent")
      else
        removable+=("$wt_dir|$reason|$parent")
      fi
    done
  done

  if [[ "${#removable[@]}" -eq 0 && "${#dirty_list[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale worktrees\033[0m\n'
    return 0
  fi

  if [[ "${#removable[@]}" -gt 0 ]]; then
    printf '\033[0;33m  Found %d stale worktree(s) safe to remove:\033[0m\n' "${#removable[@]}"
    local entry
    for entry in "${removable[@]}"; do
      IFS='|' read -r wt reason _ <<< "$entry"
      local display="${wt/#$home\//~/}"
      local reason_str
      case "$reason" in
        parent_gone) reason_str="parent gone" ;;
        not_in_parent) reason_str="not in parent list" ;;
        *) reason_str="$reason" ;;
      esac
      printf '\033[2m    - %s  [%s]\033[0m\n' "$display" "$reason_str"
    done
  fi

  if [[ "${#dirty_list[@]}" -gt 0 ]]; then
    printf '\033[0;33m  Found %d stale worktree(s) with UNCOMMITTED changes (skipping):\033[0m\n' "${#dirty_list[@]}"
    local entry
    for entry in "${dirty_list[@]}"; do
      IFS='|' read -r wt _ _ <<< "$entry"
      local display="${wt/#$home\//~/}"
      printf '\033[2m    - %s  [DIRTY — inspect manually]\033[0m\n' "$display"
    done
  fi

  if [[ "${#removable[@]}" -eq 0 ]]; then
    return 0
  fi

  local do_remove=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_remove=1 ;;
    dry) do_remove=0 ;;
    *)
      _prune_ask_yes "Remove these worktrees?" && do_remove=1 || do_remove=0
      ;;
  esac

  if [[ "$do_remove" -eq 0 ]]; then
    printf '\033[2m  - Skipped (no worktrees removed)\033[0m\n'
    return 0
  fi

  local removed=0 failed=0 entry wt_path parent_path
  for entry in "${removable[@]}"; do
    IFS='|' read -r wt_path _ parent_path <<< "$entry"
    local ok=1
    if [[ -n "$parent_path" && -d "$parent_path" ]]; then
      git -C "$parent_path" worktree remove --force "$wt_path" \
        > /dev/null 2>&1 || true
      git -C "$parent_path" worktree prune \
        > /dev/null 2>&1 || true
    fi
    if [[ -d "$wt_path" ]]; then
      rm -rf "$wt_path" 2> /dev/null && ok=1 || ok=0
    fi
    if [[ "$ok" -eq 1 ]]; then
      removed=$((removed + 1))
    else
      printf '\033[0;33m  \xe2\x86\x92 failed to remove %s\033[0m\n' "$wt_path" >&2
      failed=$((failed + 1))
    fi
  done

  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 Removed %d stale worktree(s)\033[0m\n' "$removed"
  else
    printf '\033[0;33m  \xe2\x86\x92 Removed %d, %d failed\033[0m\n' "$removed" "$failed"
  fi
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

  if [[ "${#orphans[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No orphan workers\033[0m\n'
    return 0
  fi

  printf '\033[0;33m  Found %d orphan bg-spare worker(s) holding deleted cwds:\033[0m\n' \
    "${#orphans[@]}"
  local o
  for o in "${orphans[@]}"; do
    IFS='|' read -r p cwd <<< "$o"
    printf '\033[2m    - PID %s -> %s\033[0m\n' "$p" "$cwd"
  done

  local do_kill=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_kill=1 ;;
    dry) do_kill=0 ;;
    *)
      _prune_ask_yes "Kill these orphan workers?" && do_kill=1 || do_kill=0
      ;;
  esac

  if [[ "$do_kill" -eq 0 ]]; then
    printf '\033[2m  - Skipped (no workers killed)\033[0m\n'
    return 0
  fi

  local killed=0 failed=0
  for o in "${orphans[@]}"; do
    IFS='|' read -r p _ <<< "$o"
    if kill "$p" 2> /dev/null; then
      killed=$((killed + 1))
    else
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 Killed %d orphan worker(s)\033[0m\n' "$killed"
  else
    printf '\033[0;33m  \xe2\x86\x92 Killed %d, %d failed\033[0m\n' "$killed" "$failed"
  fi
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

  if [[ "${#stale[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale cost dirs\033[0m\n'
    return 0
  fi

  printf '\033[0;33m  Found %d stale cost dir(s):\033[0m\n' "${#stale[@]}"
  local d
  for d in "${stale[@]}"; do
    printf '\033[2m    - %s\033[0m\n' "$d"
  done

  local do_delete=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_delete=1 ;;
    dry) do_delete=0 ;;
    *)
      _prune_ask_yes "Delete these cost dirs?" && do_delete=1 || do_delete=0
      ;;
  esac

  if [[ "$do_delete" -eq 0 ]]; then
    printf '\033[2m  - Skipped (no dirs removed)\033[0m\n'
    return 0
  fi

  local deleted=0 failed=0
  for d in "${stale[@]}"; do
    if rm -rf "$d" 2> /dev/null; then
      deleted=$((deleted + 1))
    else
      printf '\033[0;33m  \xe2\x86\x92 failed to delete %s\033[0m\n' "$d" >&2
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 Deleted %d stale cost dir(s)\033[0m\n' "$deleted"
  else
    printf '\033[0;33m  \xe2\x86\x92 Deleted %d, %d failed\033[0m\n' "$deleted" "$failed"
  fi
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
  _prune_bound_jsonl "${home}/.claude/state/sessions.jsonl" 500 1000 "$home"
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

  if [[ "${#stale[@]}" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No stale spills\033[0m\n'
    return 0
  fi

  printf '\033[0;33m  Found %d stale spill(s):\033[0m\n' "${#stale[@]}"
  for entry in "${stale[@]}"; do
    printf '\033[2m    - %s\033[0m\n' "$entry"
  done

  local do_delete=0
  case "${PRUNE_MODE:-ask}" in
    auto) do_delete=1 ;;
    dry) do_delete=0 ;;
    *)
      _prune_ask_yes "Delete these spills?" && do_delete=1 || do_delete=0
      ;;
  esac

  if [[ "$do_delete" -eq 0 ]]; then
    printf '\033[2m  - Skipped (no spills removed)\033[0m\n'
    return 0
  fi

  local deleted=0 failed=0
  for entry in "${stale[@]}"; do
    if rm -rf "$entry" 2> /dev/null; then
      deleted=$((deleted + 1))
    else
      printf '\033[0;33m  \xe2\x86\x92 failed to delete %s\033[0m\n' "$entry" >&2
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 Deleted %d stale spill(s)\033[0m\n' "$deleted"
  else
    printf '\033[0;33m  \xe2\x86\x92 Deleted %d, %d failed\033[0m\n' "$deleted" "$failed"
  fi
}

# ── Main entry ────────────────────────────────────────────────────────────────

_prune_run() {
  _prune_backups "${HOME}"
  _prune_stale_worktrees "${HOME}"
  _prune_orphan_workers
  _prune_stale_cost_dirs "${HOME}"
  _prune_state_journals "${HOME}"
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
