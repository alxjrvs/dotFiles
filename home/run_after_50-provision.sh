#!/bin/bash
# Every-apply provisioning. Each step is idempotent and cheap when converged, so there is no
# hash gate: an `onchange` script that exited early would record its hash and never retry, and
# gh extensions before `gh auth login` is exactly that case on a fresh machine.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# Every pinned CLI. A no-op when converged; brew (script 10) installs mise itself.
mise install --yes

# gh extensions, owner-qualified because same-named community forks exist. Needs an
# authenticated gh, which on a fresh machine comes after the first apply: skip, converge next time.
if gh auth status > /dev/null 2>&1; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    printf '%s\n' "$installed" | grep -qx "$ext" || gh extension install "$ext"
  done
fi

# User-scoped MCP servers live only in ~/.claude.json, which nothing tracks (the desktop app's
# Code tab reads the same file), so a fresh machine has none until this converges them.
if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  # 1Password Environments: a stdio server inside the desktop app; human approval per call.
  op_mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
  if [ -x "$op_mcp" ] && ! jq -e '.mcpServers["1password"]' "$HOME/.claude.json" > /dev/null 2>&1; then
    claude mcp add --scope user 1password -- "$op_mcp"
  fi
  # GitHub's stdio server. Absolute paths and /bin/sh because the desktop app spawns MCP servers
  # with a bare environment. Re-registers whenever the recorded entry differs from this one.
  #
  # --exclude-tools is the WRITE BOUNDARY on this path, and it is the only one there is: a
  # PreToolUse hook matches a tool NAME, so a guard wired to `Bash` has no opinion about an
  # `mcp__github__*` call that reaches the same API with the same token.
  #
  # PR REVIEW IS ALLOWED; ISSUE CREATION IS NOT. Commenting on a pull request is participating
  # in work already under way — the review tools below are all PR-only and stay enabled.
  # What is excluded is the issue surface, which needs nothing but a repo name to reach.
  #
  # `add_issue_comment` is the awkward one and is excluded on purpose. GitHub models a
  # top-level PR comment AS an issue comment, so that single tool cannot tell a PR thread from
  # a stranger's issue tracker. `gh` can — `gh pr comment` and `gh issue comment` are separate
  # verbs — so top-level PR comments go through gh, which is allowed, and the tool that cannot
  # express the distinction stays off. Drop it from this list if that split ever costs more
  # than it buys.
  #
  # Everything the completion path uses (create_pull_request, merge_pull_request,
  # update_pull_request, the repos tools) is untouched. Names verified against
  # `github-mcp-server generate-docs`; an unknown name here is ignored silently, so re-check
  # them after a server bump.
  shims="$HOME/.local/share/mise/shims"
  if "$shims/github-mcp-server" --version > /dev/null 2>&1; then
    no_write=add_issue_comment,issue_write,sub_issue_write
    cmd="GITHUB_PERSONAL_ACCESS_TOKEN=\"\$($HOME/.local/bin/op-sa read op://claude-agent/claude-git-pat/credential)\" exec $shims/github-mcp-server stdio --toolsets context,repos,issues,pull_requests,actions --exclude-tools $no_write"
    want=$(jq -cn --arg cmd "$cmd" '{type: "stdio", command: "/bin/sh", args: ["-c", $cmd]}')
    have=$(jq -c '.mcpServers.github // empty | {type, command, args}' "$HOME/.claude.json" 2> /dev/null || true)
    if [ "$have" != "$want" ]; then
      [ -z "$have" ] || claude mcp remove --scope user github
      claude mcp add-json --scope user github "$want"
    fi
  fi
fi

# The agent's GitHub PAT, copied from the vault into the login keychain on every apply. It lives
# here rather than in a runbook because `chezmoi apply` is the one moment a machine runs OUTSIDE
# Claude Code's Bash sandbox, which is the only place `op` can reach the vault at all.
#
# Four traps dictate the exact shape below, and all four are in docs/GOTCHAS.md under 1Password:
# written by git's own helper and never by `security`; the value passed on stdin; `erase` before
# `store`; `erase` rather than `security delete-internet-password`. Each looks like an obvious
# simplification and each one breaks a different machine. Read those entries first.
#
# Every prerequisite sits in the `if` condition, so a failure skips the block rather than aborting
# the apply: no service-account token yet, offline, or a `git` that cannot run at all converges on
# the next apply.
if [ -x "$HOME/.local/bin/op-sa" ] &&
  _helper="$(git --exec-path)/git-credential-osxkeychain" && [ -x "$_helper" ] &&
  _pat=$("$HOME/.local/bin/op-sa" read op://claude-agent/claude-git-pat/credential 2> /dev/null) &&
  [ -n "$_pat" ]; then
  for _host in github.com gist.github.com; do
    printf 'protocol=https\nhost=%s\nusername=claude-agent\n\n' "$_host" | "$_helper" erase || true
    printf 'protocol=https\nhost=%s\nusername=claude-agent\npassword=%s\n\n' "$_host" "$_pat" |
      "$_helper" store ||
      echo "provision: could not store the agent PAT for $_host — agent pushes will prompt" >&2
  done
fi
unset _pat _helper _host
