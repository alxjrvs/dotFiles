# `dot` Dispatcher Audit — Decision Report

**Scope:** post-flatten worktree at `/Users/jarvis/Code/dotFiles/.claude/worktrees/Flatten` — 2,501 lines total: `dot` (58) + `sync` (317) + `doctor` (354) + `lib/common.sh` (30) + `bootstrap.sh` (30) + `install/*` (1,153) + `share/claude-statusline/*` (559).

---

## 1. Does `dot` own too much?

**Not in its core. Around its core, yes — decisively.**

The provisioning core — dispatch, sync engine, `link()`, brew/mise/macos/claude modules — is ~1,015 lines of mostly thin, justified wrapping of stock tools (`brew bundle`, `mise install`, `defaults write`, the official Claude installer), with real correctness engineering: the ERR-trap latch in `sync` (lines 217–237) that catches mid-module failures masked by later successes, the `--only` typo guard, non-TTY-safe prompts, the `.bak`-deletion safety guard. Two pieces are genuinely bespoke *and* genuinely earn it:

- **`install/90-macos.sh`** — the declarative 18-entry defaults table with `macos_audit()` drift detection. No stock tool does the audit half. This is the best code in the repo.
- **The fresh-machine sequencing in `install/00-brew.sh` + `install/30-mise.sh`** — Homebrew self-install, Xcode CLT gate, `MISE_CONFIG_FILE` pinning before the symlink exists, mid-run shims PATH re-export so later modules see mise binaries. This ordering logic *is* the zero-thought guarantee, and no alternative provides it.

The problem is concentrated in three peripherals totaling **~1,400 lines (56% of all code)**, none of which is "sync my config":

| Periphery | LOC | Diagnosis |
|---|---|---|
| `install/95-prune.sh` | 486 | Largest file in the system. Pass 1 cleans `.bak` files that exist *only because `link()` creates them* — a self-inflicted problem. Passes 2–3 (stale Claude worktrees, orphan `--bg-spare` workers) manage Claude Code's runtime lifecycle, not dotfiles; pass 3 papers over an upstream bug with an lsof + ancestor-pid walk. |
| `doctor` | 354 | Half of it greps magic strings ("ready to brew", "No problems found") out of stock doctors the user can run directly — brittle and informationally empty. Its 27-row expected-symlinks table is a hand-maintained duplicate of `40-symlinks.sh`, a drift hazard the script itself has to warn about (lines 147–150: code written to mitigate a problem that exists only because the table is duplicated). |
| `share/claude-statusline/` | 559 | The best artifact in the repo — and provisioning-unrelated. It already has its own README, curl install, and bash-3.2 portability constraint. It is *designed* as a standalone shareable drop-in; keeping it inside the plumbing dilutes both. |

**Verdict: `dot` doesn't own too much in its core; it owns too much around its core.**

---

## 2. How to streamline (ordered, concrete)

Do these in order. Items 1–4 are low-risk and unambiguous; items 5–6 need a beat of judgment; item 7 needs your sign-off (security posture).

1. **Gut `95-prune.sh`** (saves ~430 + ~25 in `sync`; risk: low). Delete pass 2 (Claude worktrees — `git worktree prune` + Claude Code's own lifecycle cover it) and pass 3 (orphan workers — belongs in a personal script or an upstream bug report, not the machine provisioner). Shrink pass 1 to a ~50-line guarded `find ~ ~/.config ~/.claude ~/.ssh -maxdepth 4 -name '*.bak*'` loop with one Y/n prompt, keeping the `_prune_bak_is_safe` live-sibling-is-repo-symlink guard. This also lets `sync` drop the `ulimit` raise and the special-case 95-prune sourcing dance (lines 249–257, 281–297).

2. **Extract `share/claude-statusline/` to its own repo** (relocates ~559 + golden fixtures; risk: low). It gains visibility and copyability standalone — your "shareable" value argues for extraction, not deletion. `dot-claude/settings.json` points at the installed path; its own curl installer (or `60-claude.sh`) drops it into `~/.local/bin`. Golden fixtures and verify scripts move with it. The `dot statusline` dispatch rows go away.

3. **Single source of truth for the symlink table** (saves ~60 net; risk: low). Extract the pairs in `40-symlinks.sh` into a data function emitting `src|dst` lines; `_symlinks_run` loops it, `doctor` sources the module and audits the same pairs — deleting doctor's 27-row `_expected_links` array (lines 95–138) and the stale-row warning. Doctor already sources `90-macos.sh` for `macos_audit`; the pattern exists. This kills an entire failure class, not just lines.

4. **Trim doctor's stock-doctor wrappers** (saves ~50; risk: low). Drop the `brew doctor` / `mise doctor` (with its PATH-strip workaround for a self-created false positive) / `claude doctor` sections (lines 227–270). Keep what's bespoke and useful: git identity, tool presence, symlink integrity, brew bundle drift, gh auth, `mise --missing`, defaults drift, SSH chain.

5. **Delete legacy-cleanup blocks and `80-git-maint.sh`** (saves ~65; risk: low). The dotctl-migration cleanup in `40-symlinks.sh` (lines 30–35, 140–168) is one-shot code both machines have already run; a copier should never see it. `git maintenance start` for a tiny repo is a one-time manual command, not a convergence concern.

6. **Collapse `40-symlinks.sh`'s 16 tags to one or two** (saves ~15 + interface surface; risk: low). Linking is sub-second and idempotent; `--only=karabiner` saves nothing over `--only=symlinks`, and every extra tag is another way to hit the documented `--only` typo gotcha.

7. **Replace the bespoke signing agent with 1Password-native `op-ssh-sign`** (saves ~90 in `45-ssh.sh` + ~30 in doctor + the `git-ssh-sign` wrapper; risk: medium — **confirm before doing**). `45-ssh.sh` runs a second hand-rolled ssh-agent with fixed-socket lifecycle management to do what 1Password ships as a product feature — and the stack already trusts the 1Password agent for auth. Keep only the `allowed_signers` append and signingkey convergence (~30 lines). The only functional loss is signing while 1Password is locked — a non-issue on a personal interactive machine. This is the one *core* module that violates your own native-over-special rule.

**End state: roughly 2,500 → ~1,150–1,250 lines** in this repo (statusline alive and thriving elsewhere), with the deleted 1,300 lines being almost entirely the code another engineer would *not* admire — and the surviving code being exactly the part they would.

---

## 3. Would an existing project be better?

### The tension, resolved

"Native over special" pulls toward a stock tool. But look at what the stock tools actually cover:

| Responsibility | chezmoi | GNU Stow | yadm | dotbot | Nix HM (+darwin) | bare git |
|---|---|---|---|---|---|---|
| Bootstrap + dispatch | **Full** | None | Partial | Partial | Partial | Partial |
| Symlinks/file placement | Partial (copies, not links) | Partial (no renames, no modes) | Full (by elimination) | **Full** (with `.bak`-policy regression) | Full (store-path links) | Full (by elimination) |
| Brew + CLT gate | Partial (trigger only) | None | None | Partial (3rd-party plugin) | Partial (needs nix-darwin + nix-homebrew) | None |
| mise ordering + PATH bootstrap | Partial (trigger only) | None | None | None (subshells break it) | None (philosophical conflict) | None |
| macOS defaults **apply** | Partial | None | None | None | **Full** (nix-darwin) | None |
| macOS defaults **drift audit** | None | None | None | None | None | None |
| SSH signing convergence | None | None | None | None | Partial (easy 10%) | None |
| Doctor (bespoke audits) | Partial (verify/diff only) | Partial (`-n -R -v`) | Partial (`yadm status`) | None | None | Partial (`config status`) |
| Prune | Partial (root cause dissolves) | Partial (same) | Partial (same) | None | None (adds GC chores) | Partial (same) |
| Statusline | None | None | None | None | None | None |
| **Migration cost** | medium | medium | medium | medium | **high** | high |
| **Verdict** | partial-replace | not worth it | not worth it | not worth it | not worth it | not worth it |

The pattern is unmistakable: **every alternative fully covers only file placement — the ~225-line subsystem that is already the best-understood, least-buggy part of `dot` — and punts on the orchestration that is the actual zero-thought value.** Homebrew self-install, the CLT gate, mise's fresh-machine PATH sequencing, the defaults table + drift audit, SSH signing convergence, verified MCP registration: under every tool above, that bash survives nearly verbatim, just relocated into `run_onchange_` scripts, YAML `shell:` strings, Nix activation hooks, or a yadm bootstrap — frequently with *worse* failure semantics than `sync`'s ERR-latch, tag filter, and failure summary.

So "native over special" cuts the other way here: the native tools (`brew bundle`, `mise`, `defaults`, `claude`, `op`) are *already being called directly* by thin bash. Every manager above interposes a new special layer — Go templates and mangled filenames (chezmoi), a Perl dep and tree restructuring (Stow), a 5,000-line bash program plus bare-repo ergonomics (yadm), Python + YAML-wrapped bash invisible to shellcheck (dotbot), an entire second operating model (Nix), or a permanent alias-wrapped git workflow that confuses every tool including Claude Code itself (bare repo). For a post-flatten, single-host, macOS-only, no-plaintext-secrets repo, their differentiating features (multi-machine templating, alternates, encryption, secret injection into files) are precisely what you've deliberately removed — and chezmoi's celebrated `onepasswordRead` templating would actively *violate* your secrets policy by resolving plaintext into target files at apply time.

Specific disqualifiers worth naming:
- **chezmoi** (the strongest): copies, not symlinks — the edit-in-place-and-it's-live workflow dies; symlink mode explicitly can't cover your executable/private files; ~1,000 lines of provisioning bash survive as `run_` scripts anyway.
- **dotbot**: `force: true` is destructive with no `.bak`/interactive policy — a direct violation of your stated `link()` guardrail.
- **Nix**: three stacked frameworks plus a new language and a /nix daemon to replace ~1,015 lines of thin wrappers, while deleting mise and the Lean-A policy or keeping them as escape-hatch bash inside Nix strings. Fails your native test as "a second operating model," not stock macOS.
- **Stow / yadm / bare git**: cover 1 of 13 responsibilities, force repo restructuring (mirrored trees or $HOME-as-worktree) that destroys the topic-folder legibility and, for yadm/bare-git, the normal-checkout workflow your CI, bats, lefthook, and Claude Code worktrees depend on — this very audit ran in `.claude/worktrees/Flatten`, a model that doesn't exist when $HOME is the worktree.

### The call

**Keep `dot`. Streamline per section 2. Adopt no manager.** The honest accounting: a manager would replace ~225–850 lines of the code you understand best, add its own DSL/runtime/ownership model, and leave the 1,000+ lines of real provisioning logic untouched — while the streamline path deletes ~1,300 lines of the code you understand *least well in six months* (prune's pid-walking, doctor's output-grepping) and keeps the repo at "just bash, git, jq."

### If you did adopt one anyway: realistic chezmoi end-state

`sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply alxjrvs` becomes a genuinely best-in-class day-0 bootstrap (no pre-installed git needed), and `chezmoi verify`/`diff` replace the symlink audit for free. But the end-state repo is: attribute-mangled filenames (`private_dot_ssh`, `executable_dot_local…`), the brew/CLT/mise/defaults/SSH/Claude bash surviving as `run_onchange_` scripts with hash-comment idioms, the defaults *audit* and SSH-chain check still bespoke in a residual doctor, no tag filter or failure summary, and every config tweak gated behind `chezmoi edit` + `apply` instead of being instantly live. You'd trade ~850 lines of orchestration you own for a framework's conventions and a day-2 ergonomics regression — a sideways move, not a reduction. That's the *best* case among the six.

---

## Bottom line

| Question | Answer |
|---|---|
| Does `dot` own too much? | Around the core, yes: 56% of the code is three peripherals (prune, doctor's redundant half, statusline). The core itself is lean and well-built. |
| Can it stay zero-thought while shrinking? | Yes — all seven streamline ops preserve one-command provision and idempotence; several *improve* it (fewer failure modes, one symlink truth source). |
| Better stock tool? | No. Every candidate replaces the trivial part and keeps the valuable part as your bash in worse clothing. `dot` already *is* the thin glue over native tools that "native over special" asks for. |

Files referenced: `/Users/jarvis/Code/dotFiles/.claude/worktrees/Flatten/sync`, `.../doctor`, `.../install/40-symlinks.sh`, `.../install/45-ssh.sh`, `.../install/90-macos.sh`, `.../install/95-prune.sh`, `.../share/claude-statusline/statusline.sh`.


---

## Open decision

### Extract the 559-line Claude Code statusline (22% of the repo, the largest single artifact and the one already designed as a standalone shareable drop-in) into its own repository?
- **Extract to its own repo** — Move share/claude-statusline/ + golden fixtures + verify scripts to a dedicated repo with its existing README and curl install; dot-claude/settings.json points at the installed binary path. The dotfiles repo drops to pure provisioning (~1,200 lines after the full streamline), and the statusline gains the visibility and copyability a showpiece deserves. Recommended.
- **Keep it in-tree** — Leave the statusline inside dotFiles, keeping dot statusline / dot subagent-statusline dispatch and the golden-fixture test weight here. One repo to maintain, but the provisioning plumbing and the showpiece continue to dilute each other, and the repo stays ~45% non-provisioning code even after gutting prune and trimming doctor.

---
_Generated by the `audit-dot` Fable workflow (map -> assess -> 6 parallel stock-tool evaluations -> synthesize). Recommendation: **keep-and-streamline**._

