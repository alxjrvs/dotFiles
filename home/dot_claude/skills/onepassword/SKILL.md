---
name: onepassword
description: Keep the personal 1Password account in order: where a secret lives, how a repo references it, how agents read it, and a names-only audit. Use before adding, moving, renaming or rotating a 1Password item or vault, before writing an `op://` reference or a `.env` file, when setting up a project's secrets or Environment, or for "audit 1Password", "where does this key go", "add a secret".
---

# onepassword

The personal account only. A work account's vaults are its owner's: never list, move or audit them.

An agent never sees a value. It reads metadata (vault and item names, categories, tags, field
labels), writes `op://` addresses, and hands values to the program that needs them with
`op run --env-file=F -- CMD`. Nothing it runs puts a value on stdout, in a file, or in a command
argument.

## Where a secret lives

| Vault | Holds |
|---|---|
| `<Project>` | One per project: its dev and service credentials, plus the logins for its own accounts |
| `<Project>-CI` | Only when a service account deploys it: the items CI resolves, and nothing else |
| `<Project> — Admin` | Billing, banking, legal: what no machine may read |
| `claude-agent` | Credentials every agent uses across projects (gh, Anthropic, Cloudflare agent keys) |
| `Private`, `Household` | Personal items only, never a project credential |
| `Archive` | Retired items, kept restorable |

- **One source of truth.** A secret is stored once, in the vault of the project that issues it.
  Another project references that item by `op://`. A pointer note in its own vault may say where
  the item lives, but never holds the value. Before creating an item, search every vault's titles
  for it.
- **Names, kebab-case.** Items and fields are named `like-this`, because references resolve by
  literal name. Never reference an item by ID: `op item move` gives it a new one, and the
  reference breaks silently.
- **Retire, don't delete.** A dead item gets tagged `status/dormant` and moves to `Archive`. Deleting
  an item or a vault is the owner's call. Before retiring an item, rename it (`<name> (retired)`).
  `op run` also resolves a name against archived items, so an archived item and its replacement
  under the same name make the reference fail.
- A "Sign in with" login can't be moved by the CLI. Say so and let the owner move it in the app.
- **Creating an item with values:** `op item create --title T --vault V --template <(jq …)`.
  The pipe keeps the values off disk and out of argv. `op item create -` (stdin) silently ignores
  the JSON and creates an empty item.

## How a repo references one

- Each job gets a committed file, `.1password/env/<job>.env` (or a `*.op.env`), of
  `NAME=op://vault/item/field` lines, run as `op run --env-file=… -- CMD`. Never a plaintext `.env`
  value, and never an inline `op://` in a workflow.
- Local dev values live in a 1Password **Environment** named `<Project> Dev`, linked to the vault
  items rather than holding copies, and mounted at `~/.config/<project>/dev.env`, outside the repo,
  so every worktree shares it. The CLI can't create one yet: the owner does that in the app (or an
  agent, through the 1Password MCP server, with the owner's approval).
- To check that a file resolves, print names only:
  `op run --env-file="$f" -- sh -c 'for n in A B; do eval "v=\${$n:-}"; [ -n "$v" ] && echo "$n ok" || echo "$n EMPTY"; done'`

## How a machine reads one

- **CI:** a service account per project, read-only on `<Project>` and `<Project>-CI`, with its token
  in the CI provider's secret store. Binfinite's `binfinite-ci-actions` is the example.
- **Agents on this Mac:** the shared agent service account, read-only on `claude-agent` and the
  project vaults, never `Private`, `Household`, `Archive`, Break Glass or an `— Admin` vault. Its
  token is in the login keychain as `op-claude-agent`. A service account's vaults are fixed when it
  is created, so giving it a new vault means creating a new one and replacing the keychain entry.
  Rotate it before its expiry.

## Audit

`bash ~/.claude/skills/onepassword/audit.sh [~/Code]` reads metadata only. It prints:

- project credentials sitting in `Private`
- titles that appear in more than one vault (a second copy, or a pointer that should be tagged `pointer`)
- `status/dormant` items outside `Archive`, and empty vaults
- every `op://` reference under the code folder whose vault or item doesn't exist, or that uses an item ID
- `.env` files with values that aren't `op://` references (variable names only)

Fix what is unambiguous on a branch. Each move or rename changes the account, so name it to the
owner first.
