# FLATTEN — the plan

**North star: small, exemplary, shareable.** This repo's next reader is a senior engineer deciding whether to copy it. The plan below removes everything that is special without a strong reason — port-era test scaffolding, a multi-host overlay system with nothing in it, eleven dependencies with zero recorded use, a template renderer no template uses, and wrappers that merely rename native commands — and converts the two biggest bespoke surfaces (the prompt renderer, the inlined-helper duplication) toward native/stock equivalents now that the owner has reopened those principles. The Claude statusline stays bespoke by explicit owner decision (its subagent sibling gets a behavior-identical rewrite at 1/5 the size). Every cut below survived adversarial verification; refuted candidates were dropped or moved to "Considered & kept."

**TOTALS: Tier-1 alone — 11 deps removed, ~41 files removed, ~2,700 lines saved. Full plan if all owner calls land — up to ~25 deps, ~46 files, ~4,000 lines (≈35% of the repo's shell/test surface).**

Measured baselines: tests surface = 2,087 lines / 34 files (bats 877, verifiers 286, run-golden 316, HARNESS 160, fixtures 448). Prompt stack = 924 lines (git-data 450, prompt-render 373, 50-prompt.zsh 101). Subagent statusline = 236 lines.

---

## Tier 1 — Safe cuts (default APPLY, ship unattended)

Ordered by leverage. Owner directives 5 (tests), 2 (single config), and 7 (no gratuitous wrappers) are decisive here.

- [ ] `tests-golden` tests/golden/ + tests/verify-golden.sh + tests/verify-statusline.sh — delete the entire golden-snapshot harness: 26 fixtures, run-golden.sh (316 ln, compares against a Rust binary deleted months ago), HARNESS.md (160 ln, actively wrong about the hash function and a `shared/` dir that doesn't exist), both verifiers (~1,210 lines, 30 files) — risk: low per owner directive; loses the only byte-exact rendering net. Intent: port-era scaffolding whose reference target no longer exists. Effect: rendering changes are eyeballed, not diffed; re-baseline ceremony disappears.
- [ ] `tests-bats-smoke` tests/bats/ — collapse 4 suites (877 ln) to one ~80-line smoke.bats keeping only the highest-stakes guards: prune's non-TTY-never-deletes + .bak-guard tests (the one subsystem wielding `rm -rf`), link() non-interactive skip, and the symlink→doctor derivation test (~800 lines, 3 files) — risk: low-medium; drops the PR-TTL regression pin and ssh key-overwrite guard. Intent: keep a single tripwire on destructive ops, drop the receipt/idiom/duplicate tests. Effect: `bats tests/bats/` runs in ~2s; the four grep-the-source "refactor receipts," the 5 drifted inline-zsh tests, and the duplicate link() test all go.
- [ ] `tests-ci` .github/workflows/test.yml — delete CI entirely (38 ln + all runner minutes) — risk: medium (loses the only --no-verify-proof gate and PR checks); accepted per directives 5/8. Intent: CI was a strict subset of lefthook; with bats reduced to a smoke file it gates nothing real. Effect: pushes are gated only by local lint; CLAUDE.md Tests section rewritten to match.
- [ ] `tests-lefthook` lefthook.yml — drop the entire pre-push block (bats, doctor, golden verify); keep pre-commit shellcheck + shfmt and the settings-json jq check (~30 ln) — risk: low. Intent: lint catches real shell bugs in a shell repo; the settings check guards a file that breaks every Claude session if malformed — both earn their weight concretely; the rest was ceremony. Effect: pre-commit stays fast and useful; pre-push is free.
- [ ] `single-config` Brewfile.air + Brewfile.pro + install/00-brew.sh:53-67 + install/90-macos.sh:34-95 — collapse the multi-host overlay system: delete both comment-only host Brewfiles, the overlay brew-bundle loop, the empty _MACOS_AIR/PRO_OVERLAY arrays and the never-fired merge logic; retire `--host=` and host_id once consumers are gone (~75 ln, 2 files) — risk: low; both overlay arrays and both files are verifiably empty. Intent: owner wants ONE config; the overlay mechanism has never diverged anything. Effect: one Brewfile, one defaults list, no host detection; CLAUDE.md "Multi-host overlays" section deleted. Re-adding a host file later is a 5-line guard if ever truly needed.
- [ ] `sub-1-rewrite` share/claude-statusline/subagent-statusline.sh — rewrite the 236-line bash loop as a single jq program (~190 ln saved; O(1) forks instead of 2×jq+awk per task) — risk: low. Intent: pure JSON→JSON transform jq does natively; statusline stays bespoke per owner, just 1/5 the size. Effect: identical output (verify against goldens BEFORE `tests-golden` lands — sequence this first in the PR); also subsumes the gdate/now_ms cut (`sub-3-gdate`). Watch: jq has no %.1f, and preserve the malformed-input→`{"tasks":[]}` path.
- [ ] `core-1-render` render + dot:37,52 + lefthook/CI globs + Brewfile:32 comment — delete the op:// template resolver wholesale (99 ln + dispatcher row) — risk: low. Intent: zero templates use its syntax anywhere; native `op inject` does the same job if ever needed. Effect: `dot render` gone; secrets patterns 1-4 unaffected (none use it).
- [ ] `mod-linux` install/10-linux.sh + install/20-sheldon.sh Linux branch — delete Linux support (~56 ln, 1 file) — risk: low. Intent: a macOS repo for two Macs; Linux sync is already broken (symlinks are darwin-guarded, so a Linux box gets a .zshrc sourcing nothing). Effect: dead-on-arrival capability removed; `--only=linux` correctly trips the typo guard.
- [ ] `mod-sheldon-fold` install/20-sheldon.sh → tail of install/30-mise.sh — after the Linux cut, fold the remaining `sheldon lock` into 30-mise keeping both tags (1 file, ~20 ln net) — risk: low. Intent: correctness fix, not file golf — sheldon is installed BY mise, so today's ordering silently skips the lock on a fresh machine with a misleading "may be offline" message. Effect: fresh-machine bootstrap actually locks plugins.
- [ ] `deps-unused` Brewfile + mise.toml — drop moreutils, coreutils, yq, dust, gdu, glow, tealdeer (7 deps; tealdeer is also the manifest's only from-source cargo build) — risk: low. Intent: zero repo references for all seven; the Brewfile's own `jq|sponge` justification is fictional; subagent elapsed-time has a designed `date` fallback. Effect: leaner manifests, faster `mise install`; edit the Brewfile comment block and README tool list in the same change.
- [ ] `zsh-dead-tools` zsh/80-functions.zsh + zsh/70-aliases.zsh:33 + zsh/60-tools.zsh:11 + mise.toml + doctor:277-283 — delete the zero-use tool stacks: pueue (5 aliases + daemon autostarted in EVERY shell + doctor check + dep; 1 use in 3 months), watchexec + dev() (0 uses), bottom + btop alias (0), zoxide (z=0 vs cd=131), claude-fix, mkcd/cdroot/sz (all 0) (~45 ln + 4 mise deps + 1 always-running daemon) — risk: low; everything is retypeable or one-line reinstallable. Intent: the dependency bar — none proved weight. Effect: no background daemon per login, 4 fewer deps, README list updated.
- [ ] `zsh-alias-prune` zsh/70-aliases.zsh — delete the zero-use aliases (gc ga gaa gb gl gds gab la ll lt tree b c q dots env-sync env-doctor) and the `v=nvim` third editor name; keep the proven set (gs gp gpr gco gd ls vim→nvim) (~20 ln) — risk: low (worst case: type the full command). Intent: directive 7 — two names for one command is the special being eliminated; env-sync/env-doctor duplicate `dot sync`/`dot doctor` verbatim. Effect: alias file halves; update the stale gab comment in lazygit/config.yml. (Note: `b`/`ll`/`lt` carry eza/bat flags — if you use them interactively despite 0 recorded hits, strike them from this line; atuin history is single-machine evidence.)
- [ ] `wrap-1-ghostty-shim` install/50-ghostty.sh — delete the ghostty PATH shim and its module (43 ln, 1 file) — risk: low. Intent: uniformity-for-its-own-sake; zero consumers, and the CLAUDE.md claim that doctor runs `ghostty --version` is stale (doctor only checks the config symlink, which stays). Effect: nothing observable; fix the CLAUDE.md Ghostty paragraph; ghostty the app (protected) is untouched.
- [ ] `doctor-trim` doctor:286-347,261-275 — collapse the mise-doctor parser to grep-for-"No problems found" (keep the PATH-strip), the brew-doctor block to one warn, and fold the `_dotfiles2` re-resolve (~47 ln) — risk: low. Intent: both blocks buy a warning count the user re-derives by running the tool the message already points at. Effect: same actionability, less machinery.
- [ ] `mod-misc` install/00-brew.sh:69-78 + install/80-git-maint.sh:14-28 + install/90-macos.sh snapshot + sync:161 — delete the docker-desktop collision guard (trigger condition unreachable), the triple-redundant gitconfig.local seed, the write-only defaults snapshot (6 unread files accumulated, info-free after first converged sync), and the dead `export -f resolve_dotfiles_dir` (~65 ln) — risk: low. Intent: one-shot migrations that converged and hygiene that nothing reads. Effect: none at runtime.
- [ ] `prompt-hotpath-trim` prompt/prompt-render:245-253 + prompt/git-data:349-377 — drop the dead STATUSLINE_WORKTREE env override and human_time/GIT_CACHE_TIME (~22 ln + 1 fork per refresh) — risk: low. Intent: zero consumers for both. Effect: apply ONLY if `prompt-native-revert` (Tier-2) is declined; otherwise moot.
- [ ] `sl-1-advisor` share/claude-statusline/statusline.sh:336-340,422-425 — delete the advisor-model segment (~12 ln + 1 jq fork/refresh) — risk: low. Intent: renders only when test harnesses fabricate the key; dead on this machine. Effect: nothing visible changes; harness edits moot once `tests-golden` lands.
- [ ] `claude-config-trim` dot-claude/settings.json:12-14 + dot-claude/CLAUDE.md:11 + README.md:76 — remove the no-op worktree.baseRef (= documented default) and fix the "exactly three things" doc to list what settings.json actually carries (attribution, defaultMode:auto, notifications stay — see Considered & kept) (~3 ln + accuracy) — risk: low. Intent: restore the anti-creep guardrail's credibility; it was inaccurate at birth. Effect: docs match reality; also delete README's stale permissions.deny claim.
- [ ] `gitignore-safe-trim` .gitignore:38,45-46 — drop .playwright-mcp/ and .code-review-graph/ only; KEEP Brewfile.lock.json (skeptic refuted that part) and the yarn lines are harmless either way (~4 ln) — risk: low. Intent: residue of tools with zero repo presence. Effect: none.
- [ ] `files-1-nvimlog` /Users/jarvis/Code/dotFiles/nvim.log — rm the stray zero-byte untracked log (1 file) — risk: none. Intent: runtime litter. Effect: none.

**Tier-1 subtotal: ~2,700 lines, ~41 files, 11 deps (moreutils, coreutils, yq, dust, gdu, glow, tealdeer, pueue, bottom, watchexec, zoxide).**

---

## Tier 2 — Judgment cuts (owner's taste or moderate risk)

- [ ] `prompt-native-revert` prompt/git-data + prompt/prompt-render + zsh/50-prompt.zsh + dot:53-54 — replace the 924-line bespoke prompt stack with a native/stock prompt (~900 net lines after Tier-1 already removed its tests; ~1,400 standalone) — risk: medium (deletes the repo's flagship UX). Intent: owner explicitly reopened the "no starship" ban; this is the single biggest NATIVE-over-SPECIAL win available. Effect: pick a flavor —
  - **(A) starship**: `mise` dep + ~50-line starship.toml; keeps a powerline git-aware look via config-not-code; loses the PR cell (re-bespoking it costs ~30 lines of custom-command), OSC8 links, transient prompt, and the fork-free guarantee (starship forks per prompt). Retires two written guardrails (starship ban, fork-free hot path) — CLAUDE.md rewritten.
  - **(B) zsh vcs_info**: ~15-20 lines of stock zsh, ZERO new deps — the most copy-pasteable prompt fragment possible; loses powerline/Nord, count pips, worktree cell, PR cell, OSC8, transient prompt. Maximum-native option.
  - **(C) keep renderer, strip the PR subsystem**: ~330 lines off (TTL cache, bash-3.2 workaround, background refresh, SKIP_PR plumbing); keeps the look. Corrected fact: the statusline does NOT replicate the PR/CI signal in plain terminals (its .pr comes from Claude Code stdin) — C and A/B all genuinely lose CI-status-in-prompt.
  Migration for A/B is fully mapped in the verified evidence (consumer set: dot:53-54, 50-prompt.zsh, docs only; statusline confirmed independent).
- [ ] `consolidate-lib` sync + doctor + install/95-prune.sh → new lib/common.sh — consolidate the genuinely duplicated helpers (3× os_kind, 2× host_id, 3× resolve_dotfiles_dir, 2× mise-shims, 2× bash4-guard ≈ 150 ln) into one ~80-line lib; sync keeps `export -f` so all 12 modules change zero lines; 95-prune's sourced-vs-standalone guard block dies too (~65 net ln + 3-way drift retired) — risk: medium (rewrites a written guardrail). Intent: owner opted in — shared structure over copy-paste serves the showpiece goal; the "self-contained" rule was already half-fiction (modules consume exported helpers today). Effect: CLAUDE.md Architecture + Guardrails rewritten in the same PR (the `simplify-1` doc rider); hard exclusions verified: the statusline pair (single-file contract), `dot` (chicken-and-egg resolver), bootstrap.sh stay inline. Do NOT consolidate repo_hash (test-pinned identity pair; moot anyway if prompt revert lands). The 111-call-site logging unification (`consolidate-3`) stays deferred — ~20 net lines for a 14-file text-sensitive diff.
- [ ] `zsh-8-lazygit` lazygit + git-absorb + lazygit/config.yml + symlink + lg alias — drop the whole TUI stack (2 mise deps, 1 config file, 1 symlink, ~10 wiring sites) — risk: medium. Intent: lg=0, lazygit=0, gab=0 in 3 months while raw git ≈ 250 uses — but atuin can't see TUI launches from inside nvim/keybinds, and this has the largest coordination surface of any cut (70-aliases, mise.toml ×2, 40-symlinks, doctor:171, README ×3). Effect: if you don't launch it, this is 2 deps + a config for free; cut all wiring sites in one commit or doctor fails.
- [ ] `gitcfg-1-difftastic` .gitconfig:12,95-98 + mise.toml:32 + README:82-84 — drop the difftool wiring and dep; delta stays as the single diff surface (1 dep + ~8 ln + doc section) — risk: low. Intent: dependency bar — delta has 5 live consumers, difftastic has only its own wiring; only `git dft` muscle memory can save it. Effect: all diffing through delta (already side-by-side + syntax-aware).
- [ ] `karabiner-native` Brewfile:59 + karabiner/karabiner.json + 40-symlinks + doctor:173 — replace Karabiner-Elements (a GUI app + daemon existing for ONE caps_lock→ctrl mapping) with macOS's native modifier remap (1 cask + 26-ln file + 2 stanzas) — risk: medium. Intent: textbook NATIVE-over-SPECIAL. Effect: same remap, zero third-party daemon. Implementation caveat (verified): `hidutil` does NOT persist across reboot — use the per-keyboard `com.apple.keyboard.modifiermapping` defaults (or System Settings UI), re-applied per keyboard vendor/product ID; also remove the README/CLAUDE.md table rows.
- [ ] `deps-offrepo` mise.toml — python 3.13, uv, heroku — cut whichever have no off-repo life (up to 3 deps, python ≈100MB+) — risk: medium (grep can't see other repos). Intent: zero in-repo consumers for all three (contrast node: 3 LSPs + doctor); per-project mise pins are the idiomatic home anyway; heroku was added deliberately 3 commits ago — lean keep unless that work is done. Effect: per-project `mise use` covers any real need.
- [ ] `deps-casks` Brewfile:42,61 — drop devutils (overlaps jq/bat/Claude) and ngrok (reinstall-on-demand); KEEP notunes (invisible-to-grep but real daily value) (up to 2 casks) — risk: medium, grep proves nothing for GUI apps. Intent: dependency bar. Effect: `brew install --cask` is the undo.
- [ ] `mod-gh-extensions` install/70-gh.sh — delete the module + `gh extension remove` gh-dash/gh-notify/gh-actions-cache if you don't run them (1 file, 41 ln, 3 third-party code surfaces with keychain-token access) — risk: medium. Intent: unused = a supply-chain win, not just lines; used = the pinning discipline is worth keeping. Effect: only you know — do you open `gh dash`?
- [ ] `zsh-9-carapace` zsh/40-completions.zsh:44-49 + mise.toml — drop the blanket-completion bridge, lean on zsh-completions + brew site-functions + native gh/fzf completions (1 dep + ~6 ln + 1 init cache) — risk: medium (unmeasurable UX). Intent: the only completion layer costing a binary. Effect: long-tail CLIs fall back to file completion; your top-10 commands all complete without it.
- [ ] `wrap-4-op-run` zsh/80-functions.zsh:13-24 + 4 doc sites — unwrap op-run to stock `op run --` and reword secrets pattern 1 in CLAUDE.md/README/mise.toml/.gitignore to teach the native spelling (~12 ln) — risk: low. Intent: every security property belongs to `op run` itself; the wrapper saves 3 characters — and teaching stock usage makes the policy MORE shareable. Effect: move the masking-rationale comment block into the CLAUDE.md secrets section; the policy itself is unchanged.
- [ ] `wrap-12-cached-load` zsh/30-plugins.zsh:9-25 — replace the bespoke init-cache with seven stock `eval "$(tool init zsh)"` one-liners (~17 ln + a cache dir + an invalidation bug class, one already bitten) — risk: medium. Intent: NATIVE-over-SPECIAL vs the repo's own latency obsession; 7 call sites (incl. slow mise/sheldon/atuin inits) save ~7 forks ≈ 50-150ms per shell. Effect: pure taste — price startup latency against the one-liner form every README teaches. (If the prompt revert lands, the latency religion is already retired; cut this too for consistency.)
- [ ] `ssh-1-augment` ssh/config:3-4 + doctor:433-437 — drop the Augment Include + doctor check as a PAIR if Augment is retired (~7 ln + 1 external coupling) — risk: low. Intent: the target file is 7.5 months stale and 'augment' appears nowhere else. Effect: if Augment is still alive its remote agents lose SSH; otherwise free.
- [ ] `gitcfg-2-boilerplate` .gitconfig lines 2-5 and 14-21 ONLY (corrected range — the literal 1-21 would destroy kept aliases) — drop tags/branches/remotes renames + both [color] sections (~12 ln) — risk: low. Intent: 2009-era boilerplate; git's default colors are good now. Effect: hist/sw/st/undo/sync/dft stay.
- [ ] `core-6-claude-doctor` doctor:349-364 — drop the `claude doctor` invocation (slowest external check, version-fragile) (~16 ln) — risk: low. Intent: you run Claude daily — you'd notice a broken install before doctor does. Effect: doctor stops vouching for the claude binary on fresh machines; that canary is the only loss.
- [ ] `set-3-inputneeded` dot-claude/settings.json:27 — verify whether `inputNeededNotifEnabled:true` is the default; if yes trim, if no keep and add to the documented list (1 ln) — risk: medium if default is false (breaks the walk-away workflow). Intent: minimal-settings discipline. Effect: test by toggling once.
- [ ] `sl-3-gradient` statusline.sh:84-108 — optionally replace the blackbody gradient with 3 threshold colors (~28 ln) — risk: low, pure taste. Intent: the heat-read is aesthetic only. Effect: your call entirely; the statusline stays regardless.
- [ ] `sl-4-projection` statusline.sh — optionally drop the burn-projection pip + delta (~30 ln) — risk: low. Intent: it's the only forward-looking signal on the rate rows you built the statusline for — lean KEEP. Effect: listed for completeness, not advocacy.

---

## Tier 3 — Principle challenges (revisit a written rule, neutrally)

- [ ] `sl-6-standalone` share/claude-statusline/README.md + the bash-3.2 constraint — the statusline's "curl-installable standalone gist" story was never shipped (the install URL is literally `<raw-gist-url>`). Native option: retire the story, delete the README, lift bash-3.2, and rewrite in bash-4+ (~50 ln now, est. 60-100 more off statusline.sh). Blocking principle: CLAUDE.md gotcha "portable as a standalone drop-in (own README + curl install)". Tension: the statusline stays bespoke per your directive — this only asks whether it must stay portable to an audience that has never existed. If you ever intend to publish the gist, keep; if not, the constraint is pure cost.
- [ ] `core-9-doctor-table` doctor:149-188 — the 27-row expected-symlinks table duplicates install/40-symlinks.sh; deriving it would save ~30 lines but requires doctor to read installer data. Blocking principle: the self-contained rule — which `consolidate-lib` retires anyway. If consolidate-lib lands, this becomes a legitimate follow-on; until then the built-in drift warning polices the duplication adequately.
- [ ] `sl-8-cache-coupling` statusline.sh:275-334 — the statusline re-gathers git state the prompt cache already has (~60 ln). Blocked by BOTH the self-contained rule and the standalone story; only viable if `consolidate-lib` AND `sl-6-standalone` both land, and even then the GIT_OPTIONAL_LOCKS=0 self-gathering is a deliberate design. Lean keep; listed so the tradeoff is on the record.

---

## Bespoke surface ledger

| Bespoke surface | Native alternative | Verdict |
|---|---|---|
| prompt/git-data + prompt-render (924 ln) | starship, or stock zsh vcs_info | **revert-to-native** (Tier-2, owner picks flavor) |
| Multi-host overlays (Brewfile.<host>, macOS merge, host_id, --host) | one shared config | **revert-to-native** (Tier-1; overlays verifiably empty) |
| Golden-snapshot harness + 4 bats suites | none — tests are ceremony here | **cut** (Tier-1, owner directive) |
| render (op:// templates) | `op inject` (built into op) | **cut** (Tier-1, zero templates exist) |
| ghostty PATH shim | app-bundle path / `open -a Ghostty` | **cut** (Tier-1, zero consumers) |
| op-run wrapper | stock `op run --` | **owner-call** (Tier-2; policy doc rewrite) |
| _zsh_cached_load init cache | stock `eval "$(tool init zsh)"` ×7 | **owner-call** (Tier-2; latency vs stock) |
| Karabiner-Elements (1 mapping) | macOS native modifier remap | **owner-call** (Tier-2; persistence caveat) |
| Inlined-helper duplication (~150 ln ×3 scripts) | small lib/common.sh | **consolidate** (Tier-2, owner opted in) |
| Claude statusline (statusline.sh) | CC default statusline | **keep-bespoke-deliberately** (owner directive) |
| Subagent statusline | CC built-in panel | **keep-bespoke, rewritten 236→~45 ln** (Tier-1) |
| bash-3.2 + unpublished gist story | bash-4+ rewrite | **owner-call** (Tier-3) |
| dual ssh-agent signing (git-ssh-sign) | 1Password op-ssh-sign | **keep-bespoke** (fixes launchd + biometric-per-commit, recent + deliberate) |
| gh-mcp-auth-header | standing PAT export (worse) | **keep-bespoke** (security: keychain-on-demand) |
| dot dispatcher | hard-coded script paths | **keep-bespoke** (6 external call sites need a stable relocatable name) |
| sync ERR-trap latch | none — inherent bash semantics | **keep** (every dense line is a constraint) |
| nvim single-file native-LSP config | — already the native design | **keep** |

## Dependency weigh-in (weakest justification first)

Protected, never on the table: **brew, neovim, ghostty.**

| Dependency | Verdict |
|---|---|
| tealdeer | **cut** — zero footprint, the manifest's only from-source build |
| yq | **cut** — zero references; everything here is jq |
| dust + gdu | **cut** — two unreferenced tools, one job |
| glow | **cut** — bat renders markdown |
| moreutils | **cut** — its own Brewfile justification is fictional |
| coreutils | **cut** — sole consumer has a designed fallback |
| pueue | **cut** — daemon in every shell, 1 command in 3 months |
| bottom | **cut** — never opened |
| watchexec | **cut** — dev()=0 uses |
| zoxide | **cut** — z=0 vs cd=131 |
| devutils, ngrok | **owner-call** — GUI casks, grep-invisible; lean cut |
| notunes | **owner-call** — lean keep (invisible but real) |
| uv, python | **owner-call** — zero in-repo use; off-repo unknown |
| heroku | **owner-call** — added deliberately 3 commits ago; lean keep unless done |
| difftastic | **owner-call** — only `git dft` muscle memory defends it |
| lazygit + git-absorb | **owner-call** — 0 recorded launches, biggest coordination surface |
| carapace | **owner-call** — only completion layer costing a binary |
| zsh-autopair | **owner-call** — pure typing-feel |
| gh-dash / gh-notify / gh-actions-cache | **owner-call** — unused = supply-chain win |
| karabiner-elements | **owner-call** — native remap exists (Tier-2) |
| openssl@3, bash (brew) | **keep — proven** — sheldon segfaults / render+prune need bash-4 (bash stays for prune even after render dies) |
| jq, git, gh, mise, sheldon, fzf, fd, ripgrep, bat, eza, delta, atuin, direnv, op, gitleaks | **keep — proven** — live consumers verified |
| node, rust, bun | **keep — proven** — 3 npm LSPs / rust-analyzer / stated PM |
| bats, shellcheck, shfmt, lefthook | **keep** — shrunken but retained test/lint floor |
| carapace-era LSPs (bashls, ts_ls, marksman, taplo, prettier) | **keep — proven** — wired in init.lua, sanctioned design |

## Wrapper/shim audit (directive 7)

| Wrapper/shim | Verdict |
|---|---|
| install/50-ghostty.sh shim | **cut** — uniformity-for-its-own-sake, zero consumers |
| env-sync / env-doctor aliases | **cut** — verbatim duplicates of `dot sync`/`dot doctor` |
| claude-fix() | **cut** — one baked prompt string |
| btop→btm, v→nvim | **cut** — renames that teach wrong names |
| pq* aliases + pueued autostart | **cut** — rides the pueue removal |
| dev() | **cut** — flag preset with 0 uses |
| mkcd/cdroot/sz | **cut** — legitimate composition, zero use in 3 months |
| op-run | **owner-call** — 3-char rename of `op run --`; unwrap + reword docs |
| _zsh_cached_load | **owner-call** — real fork savings ×7 vs stock one-liners |
| ssh/git-ssh-sign | **strong-reason-keep** — git config can't inject env; signing in launchd contexts depends on it |
| gh/gh-mcp-auth-header | **strong-reason-keep** — keychain token at connect time; no native headersHelper alternative |
| dot dispatcher | **strong-reason-keep** — settings.json + prompt hooks need a stable relocatable command |
| bootstrap.sh | **strong-reason-keep** — the one-command front door; stock pattern |
| vi/vim→nvim, ls/la/ll/lt/b/gab/dots | **keep** — carry real flag config (eza has no config file) — subject to the zero-use prune above |

## Considered & kept

- **5h/7d rate rows, cost line, width tiers, PR segment (statusline)** — the PR segment cut was REFUTED: `.pr` is a documented live Claude Code stdin field. The rate rows are why the statusline exists. All stay.
- **Subagent statusline as a surface** — drop-it case refuted (deliberate, documented, daily-seen); it gets rewritten, not removed.
- **delta** — 5 live consumers; the pager role stays regardless of difftastic's fate.
- **openssl@3 + brew bash** — the Lean A policy's canonical load-bearing exceptions.
- **carapace/watchexec/bottom/pueue/git-absorb as a block ("Tier-3 escapees")** — the block-keep was verified, but per-tool usage data overrode it for pueue/watchexec/bottom above; carapace and git-absorb are owner calls.
- **install/95-prune.sh** — most load-bearing module in the repo (live GC: 10+ stale worktrees, 6 orphan workers found during verification).
- **sync ERR-trap latch** — every dense line is a documented bash constraint; simplifying reintroduces the false-success bug it fixed.
- **github MCP registration + verify-after-write (60-claude.sh)** — sole provisioning path for a live, doctor-audited integration; add-json lies about success.
- **defaultMode:auto and the attribution block (settings.json)** — both deliberately (re)added by you, days ago; the fix is documenting them (`claude-config-trim`), not deleting them.
- **dot-claude/REFERENCE.md** — unreferenced BY DESIGN ("read on demand"), rewritten during the reset; deleting freshly-curated notes is your call, not a dead-code cut. The AC-override worry was refuted (statusline already reads the env var).
- **zsh-history-substring-search** — hard-wired pairing with `atuin --disable-up-arrow`; removal dangles 4 bindkeys.
- **fzf-tab + fast-syntax-highlighting** — every-keystroke surfaces; FSH-last ordering gotcha stands.
- **repo_hash inlined pair** — byte-identity is test-pinned; moot if the prompt revert lands.
- **mod-lefthook-collapse** — refuted: one-module-per-concern is the documented design and there's no correctness win (unlike sheldon).
- **.editorconfig trim** — refuted: the cited range would break live markdown/Python defaults.
- **cfg-1 small tool configs** — all five verified live; atuin's secret_filters is a security property.
- **Deferred on timing**: `sym-1`/transitional symlink cleanups (cut only after the M2 Pro has run one post-rewrite sync — they exist precisely to converge it); GIT_PR_NUMBER field (8+ touchpoints in regression-prone code, moot if prompt goes); .gitmessage shrink; github.com ssh stanza; fzf-tab niche previews; logging-vocabulary unification; bats file rename (moot once collapsed).

---

## Recommended first PR — "the dead-weight sweep"

Pure deletions with zero behavior change, shippable unattended today (~2,300 lines, ~37 files, 11 deps):

1. `sub-1-rewrite` FIRST (verify byte-exact against the goldens while they still exist), then
2. `tests-golden` + `tests-bats-smoke` + `tests-ci` + `tests-lefthook`
3. `core-1-render`, `mod-linux`, `mod-sheldon-fold`, `wrap-1-ghostty-shim`
4. `deps-unused`, `zsh-dead-tools`, `zsh-alias-prune`
5. `single-config`, `mod-misc`, `doctor-trim`, `sl-1-advisor`, `claude-config-trim`, `gitignore-safe-trim`, `files-1-nvimlog`

One commit per numbered group; update CLAUDE.md/README in the same commits that orphan their prose. Commit FLATTEN-PLAN.md itself at the top of the PR — planning docs live in-repo. The PR after this one is the prompt decision (the single biggest remaining surface), which deserves its own focused diff.


---

## Open decisions (answer these to unlock Tier 2/3)

### Prompt — The bespoke prompt renderer (924 lines: git-data + prompt-render + zsh glue) is the biggest special surface left, and you've reopened the starship ban. What replaces it?
- **starship** — Config-not-code powerline prompt; +1 mise dep, ~50-line TOML; keeps the look, loses PR cell/OSC8/transient prompt and the fork-free guarantee. ~900 net lines off.
- **Plain zsh vcs_info** — ~15 stock lines, zero deps — maximum-native, most copy-pasteable; loses powerline/Nord, pips, PR cell, worktree cell. ~900 net lines off.
- **Keep renderer, strip PR subsystem** — Keep the look, delete the gh/TTL/bash-3.2 machinery (~330 lines). Note: the PR/CI signal is genuinely lost from plain terminals either way — the statusline's .pr only exists inside Claude Code.
- **Keep as-is** — Retain the flagship bespoke surface; apply only the 22-line hot-path trim (dead env override, dead cache fields).

### Git tooling — lazygit (+ git-absorb keybinding) and difftastic show zero recorded use in 3 months while you drive git from the CLI (~250 uses) — but TUI launches and `git dft` are invisible to history. Cut the stack?
- **Cut all three** — Drop lazygit, git-absorb, difftastic: 3 mise deps, lazygit/config.yml, 1 symlink, ~10 wiring sites. delta stays as the single diff surface.
- **Cut difftastic only** — Lowest-risk slice: difftool wiring + dep + README section; keep lazygit/git-absorb untouched.
- **Keep everything** — You actually launch lazygit (from nvim or muscle memory) — keep the stack, kill only the stale gab-alias comment.

### Karabiner — Karabiner-Elements (GUI app + daemon + config + symlink + doctor stanza) exists for exactly one caps_lock→left_control mapping. Replace with macOS's native modifier remap?
- **Go native** — Per-keyboard com.apple.keyboard.modifiermapping defaults (NOT hidutil — it doesn't survive reboot); drops 1 cask, 1 daemon, 26-line config, 2 stanzas. Re-apply once per new external keyboard.
- **Keep Karabiner** — Keep the set-and-forget app and the option of future complex modifications; accept one resident third-party daemon for one keystroke remap.

### Off-repo deps — python 3.13, uv, and heroku have zero in-repo consumers, but grep can't see your other projects. heroku was added deliberately three commits ago. Which go?
- **Cut python + uv, keep heroku** — Per-project mise pins cover any real Python work (~100MB+ back); heroku's recent deliberate add suggests active use.
- **Cut all three** — The Heroku work is done; everything reinstalls per-project in one line when needed.
- **Keep all three** — Active off-repo Python and Heroku workflows exist; global toolchains are the convenience you want.

---
_Generated by the `flatten-dotfiles` Fable workflow (8 surfaces + 3 deep-dives → propose → adversarial challenge → synthesize). 126 candidates, 114 survived verification._

