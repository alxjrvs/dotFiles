#!/usr/bin/env bash
# Names-only audit of the personal 1Password account against the onepassword skill's rules.
# Reads vault and item metadata (`op vault list`, `op item list`) and never an item's fields.
# Usage: bash audit.sh [code-dir]   (default ~/Code). OP_ACCOUNT selects the account.
set -euo pipefail

code="${1:-$HOME/Code}"
acc=(--account "${OP_ACCOUNT:-my.1password.com}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

op vault list "${acc[@]}" --format=json > "$tmp/vaults.json"
op item list "${acc[@]}" --format=json > "$tmp/items.json"

section() { printf '\n== %s\n' "$1"; }

section "Project credentials in Private (API credentials, SSH keys, databases)"
jq -r '.[] | select(.vault.name == "Private" and (.category == "API_CREDENTIAL" or .category == "SSH_KEY" or .category == "DATABASE"))
  | "  \(.title)  [\(.category)]"' "$tmp/items.json"

section "Titles in more than one vault (a copy, or a pointer that should be tagged 'pointer')"
jq -r 'map(select(.vault.name != "Archive" and ((.tags // []) | index("pointer") | not)))
  | group_by(.title | ascii_downcase)[] | select((map(.vault.name) | unique | length) > 1)
  | "  \(.[0].title): \(map(.vault.name) | unique | join(", "))"' "$tmp/items.json"

section "Dormant items outside Archive"
jq -r '.[] | select(((.tags // []) | index("status/dormant")) and .vault.name != "Archive")
  | "  \(.vault.name) / \(.title)"' "$tmp/items.json"

section "Empty vaults"
jq -r '.[] | select(.items == 0) | "  \(.name)"' "$tmp/vaults.json"

section "op:// references under $code that don't resolve to a vault and item"
# --no-ignore: the gitignored .env files are the ones that matter most.
rg -o --no-filename --hidden --no-ignore -g '!node_modules' -g '!.git' -g '!dist' -g '!coverage' \
  -g '!.claude/worktrees' -g '!*.md' \
  'op://[^/"'"'"' `]+/[^/"'"'"' `]+' "$code" 2> /dev/null | sort -u > "$tmp/refs" || true
while IFS= read -r ref; do
  rest=${ref#op://}
  vault=${rest%%/*}
  item=${rest#*/}
  # Placeholders in docs and examples, not references.
  case $vault/$item in *'<'* | *'…'* | *'...'* | *'$'* | *'{'* | V/* | vault/* | VAULT/*) continue ;; esac
  if [[ $item =~ ^[a-z0-9]{26}$ ]]; then
    echo "  $ref  (an item ID: it breaks when the item moves; use the name)"
  elif ! jq -e --arg v "$vault" 'any(.[]; .name == $v)' "$tmp/vaults.json" > /dev/null; then
    echo "  $ref  (no vault '$vault')"
  elif ! jq -e --arg v "$vault" --arg i "$item" 'any(.[]; .vault.name == $v and (.title == $i or .id == $i))' "$tmp/items.json" > /dev/null; then
    echo "  $ref  (no item '$item' in $vault)"
  fi
done < "$tmp/refs"

section ".env files under $code holding values instead of op:// references (names only)"
fd -H -t f -E node_modules -E .git -E '*.example' -E '*.sample' '^\.env' "$code" 2> /dev/null |
  while IFS= read -r f; do
    names=$(awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=./ { v = substr($0, length($1) + 2); gsub(/^["'"'"']/, "", v)
      if (v !~ /^op:\/\// && $1 !~ /^(EXPO_PUBLIC_|VITE_|NEXT_PUBLIC_|PUBLIC_)/ && $1 !~ /(_URL|_DEPLOYMENT|_ID|_PERSONA)$/) printf "%s ", $1 }' "$f")
    [ -n "$names" ] && echo "  ${f#"$code"/}: $names"
  done
echo
