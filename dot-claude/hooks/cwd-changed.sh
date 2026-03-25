#!/usr/bin/env bash
# CwdChanged hook: surface meaningful project context when switching directories.
# Reads JSON from stdin with `cwd` field. Outputs JSON with `additionalContext`.
# Exit 0 always — informational only, never blocks.

set -uo pipefail

input=$(cat)
new_cwd=$(echo "$input" | jq -r '.cwd // empty')

[[ -z "$new_cwd" || ! -d "$new_cwd" ]] && exit 0

signals=()

# --- Git info ---
if git -C "$new_cwd" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$new_cwd" symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  dirty=$(git -C "$new_cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  signals+=("git: branch=$branch, $dirty uncommitted file(s)")
fi

# --- Package manager / runtime ---
if [[ -f "$new_cwd/package.json" ]]; then
  pkg_name=$(jq -r '.name // "unnamed"' "$new_cwd/package.json" 2>/dev/null)
  pkg_scripts=$(jq -r '.scripts // {} | keys | join(", ")' "$new_cwd/package.json" 2>/dev/null)
  lock="npm"
  [[ -f "$new_cwd/bun.lockb" || -f "$new_cwd/bun.lock" ]] && lock="bun"
  [[ -f "$new_cwd/yarn.lock" ]] && lock="yarn"
  [[ -f "$new_cwd/pnpm-lock.yaml" ]] && lock="pnpm"
  signals+=("node project: $pkg_name (lock: $lock)")
  [[ -n "$pkg_scripts" ]] && signals+=("scripts: $pkg_scripts")
fi

if [[ -f "$new_cwd/pyproject.toml" ]]; then
  signals+=("python project (pyproject.toml)")
elif [[ -f "$new_cwd/requirements.txt" ]]; then
  signals+=("python project (requirements.txt)")
fi

if [[ -f "$new_cwd/Cargo.toml" ]]; then
  signals+=("rust project (Cargo.toml)")
fi

if [[ -f "$new_cwd/go.mod" ]]; then
  mod_name=$(head -1 "$new_cwd/go.mod" 2>/dev/null | sed 's/^module //')
  signals+=("go project: $mod_name")
fi

# --- Framework detection ---
if [[ -f "$new_cwd/next.config.ts" || -f "$new_cwd/next.config.js" || -f "$new_cwd/next.config.mjs" ]]; then
  signals+=("framework: Next.js")
elif [[ -f "$new_cwd/astro.config.mjs" || -f "$new_cwd/astro.config.ts" ]]; then
  signals+=("framework: Astro")
elif [[ -f "$new_cwd/vite.config.ts" || -f "$new_cwd/vite.config.js" ]]; then
  signals+=("framework: Vite")
elif [[ -f "$new_cwd/nuxt.config.ts" ]]; then
  signals+=("framework: Nuxt")
fi

# --- Monorepo signals ---
if [[ -f "$new_cwd/turbo.json" ]]; then
  signals+=("monorepo: Turborepo")
fi
if [[ -f "$new_cwd/pnpm-workspace.yaml" || -d "$new_cwd/packages" ]]; then
  signals+=("monorepo: workspace packages detected")
fi

# --- Vercel ---
if [[ -f "$new_cwd/vercel.json" || -f "$new_cwd/vercel.ts" || -f "$new_cwd/.vercel/project.json" ]]; then
  signals+=("deployment: Vercel project")
fi

# --- Docker ---
if [[ -f "$new_cwd/Dockerfile" || -f "$new_cwd/docker-compose.yml" || -f "$new_cwd/docker-compose.yaml" || -f "$new_cwd/compose.yaml" ]]; then
  signals+=("docker: containerized")
fi

# --- Project instructions ---
if [[ -f "$new_cwd/CLAUDE.md" ]]; then
  signals+=("CLAUDE.md present (project instructions loaded)")
fi
if [[ -f "$new_cwd/.cursorrules" ]]; then
  signals+=("note: .cursorrules file present (Cursor IDE rules)")
fi

# --- Nothing interesting ---
if [[ ${#signals[@]} -eq 0 ]]; then
  exit 0
fi

# Build context string
context="Switched to: $new_cwd"
for s in "${signals[@]}"; do
  context="$context
- $s"
done

jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
exit 0
