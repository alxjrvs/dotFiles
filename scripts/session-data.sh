#!/bin/sh
# session-data.sh — Claude Pro/Max 5-hour window cache
# Uses ccusage to query the active rate-limit block and caches the result.
# Cache file: /tmp/session-data-cache-$(id -u).sh
# Consumers: source the cache file to get SESSION_* variables.
#
# Refresh model: stale cache reads are fine; background refresh runs when the
# cache exceeds its TTL and no lock is held. ccusage itself takes ~4s, so it
# MUST NOT run inline on the statusline hot path.
#
# Variables written:
#   SESSION_CACHE_TIME     — unix timestamp when cache was written
#   SESSION_START          — ISO 8601 start of the active 5h block (empty if none)
#   SESSION_END            — ISO 8601 end of the active 5h block
#   SESSION_REMAINING_MIN  — minutes remaining in the current block
#   SESSION_COST_USD       — cost accumulated in this block
#   SESSION_TOKENS         — total tokens consumed in this block
#   SESSION_TOKEN_LIMIT    — token limit for the block (from --token-limit). Resolved per-account
#                            via ~/dotFiles/ccusage/limits.json keyed by the logged-in Claude
#                            email (~/.claude.json oauthAccount.emailAddress). Override with the
#                            CCUSAGE_TOKEN_LIMIT env var; fallback is "max" (historical peak).
#   SESSION_BURN_PCT       — current tokens as % of limit (integer, capped at 100)

_cache_file="/tmp/session-data-cache-$(id -u).sh"
_lock_file="${_cache_file}.lock"
_ttl=60
_now=$(date +%s)

# Locate ccusage (may not be on PATH in the statusline environment)
_ccusage=""
if [ -x "$HOME/.bun/bin/ccusage" ]; then
  _ccusage="$HOME/.bun/bin/ccusage"
elif command -v ccusage >/dev/null 2>&1; then
  _ccusage="ccusage"
fi

# Age of existing cache
_age=999999
if [ -f "$_cache_file" ]; then
  _cached_time=$(sed -n "s/^SESSION_CACHE_TIME='\([0-9]*\)'$/\1/p" "$_cache_file")
  _age=$(( _now - ${_cached_time:-0} ))
fi

# Resolve token limit by logged-in Claude account.
# Lookup order:
#   1) CCUSAGE_TOKEN_LIMIT env var (explicit override, highest priority)
#   2) ~/dotFiles/ccusage/limits.json keyed by ~/.claude.json oauthAccount.emailAddress
#   3) "max" fallback (ccusage historical-peak heuristic)
_resolve_token_limit() {
  if [ -n "${CCUSAGE_TOKEN_LIMIT:-}" ]; then
    printf '%s' "$CCUSAGE_TOKEN_LIMIT"
    return
  fi
  _limits_file="$HOME/dotFiles/ccusage/limits.json"
  _claude_config="$HOME/.claude.json"
  if [ -f "$_limits_file" ] && [ -f "$_claude_config" ] && command -v jq >/dev/null 2>&1; then
    _email=$(jq -r '.oauthAccount.emailAddress // empty' "$_claude_config" 2>/dev/null)
    if [ -n "$_email" ]; then
      _lookup=$(jq -r --arg e "$_email" '.[$e] // empty' "$_limits_file" 2>/dev/null)
      if [ -n "$_lookup" ]; then
        printf '%s' "$_lookup"
        return
      fi
    fi
  fi
  printf 'max'
}

# Async refresh if stale and no refresh in flight
if [ -n "$_ccusage" ] && [ "$_age" -ge "$_ttl" ] && [ ! -f "$_lock_file" ]; then
  mkdir -p "$(dirname "$_lock_file")" 2>/dev/null
  (
    printf '%s' "$_now" > "$_lock_file"
    _limit_arg=$(_resolve_token_limit)
    _raw=$("$_ccusage" blocks --active --json --token-limit "$_limit_arg" 2>/dev/null)
    _start=""
    _end=""
    _remain=0
    _cost=0
    _tokens=0
    _limit=0
    _burn_pct=0
    if [ -n "$_raw" ]; then
      _start=$(printf '%s' "$_raw" | jq -r '.blocks[0].startTime // empty' 2>/dev/null)
      _end=$(printf '%s' "$_raw" | jq -r '.blocks[0].endTime // empty' 2>/dev/null)
      _remain=$(printf '%s' "$_raw" | jq -r '.blocks[0].projection.remainingMinutes // 0' 2>/dev/null)
      _cost=$(printf '%s' "$_raw" | jq -r '.blocks[0].costUSD // 0' 2>/dev/null)
      _tokens=$(printf '%s' "$_raw" | jq -r '.blocks[0].totalTokens // 0' 2>/dev/null)
      _limit=$(printf '%s' "$_raw" | jq -r '.blocks[0].tokenLimitStatus.limit // 0' 2>/dev/null)
      if [ "${_limit:-0}" -gt 0 ] 2>/dev/null; then
        _burn_pct=$(printf '%s' "$_raw" | jq -r '((.blocks[0].totalTokens // 0) * 100 / (.blocks[0].tokenLimitStatus.limit // 1) | floor)' 2>/dev/null)
        [ "${_burn_pct:-0}" -gt 100 ] && _burn_pct=100
      fi
    fi
    cat > "$_cache_file" <<CACHE
# session-data cache — generated $(date)
SESSION_CACHE_TIME='$(date +%s)'
SESSION_START='${_start}'
SESSION_END='${_end}'
SESSION_REMAINING_MIN='${_remain}'
SESSION_COST_USD='${_cost}'
SESSION_TOKENS='${_tokens}'
SESSION_TOKEN_LIMIT='${_limit}'
SESSION_BURN_PCT='${_burn_pct}'
CACHE
    rm -f "$_lock_file"
  ) &
fi
