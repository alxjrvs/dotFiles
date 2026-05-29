// doctor subcommand — read-only diagnostics.
//
// Replaces install/80-health.sh and adds drift detection (symlink integrity,
// dotctl version, tool presence, dead-string scan in tracked configs).
// Read-only: never modifies state. Exits non-zero if any check fails so
// it can be used in CI / pre-flight scripts.

use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const GREEN: &str = "\x1b[0;32m";
const YELLOW: &str = "\x1b[0;33m";
const RED: &str = "\x1b[0;31m";
const NC: &str = "\x1b[0m";

pub fn run() -> Result<()> {
    let mut fails = 0u32;
    let mut warns = 0u32;

    // Prepend mise shims to PATH so tool-presence checks work when doctor
    // is invoked from non-zsh contexts (CI, bash subshells, pre-push hooks).
    // .zshenv does this for zsh; dotctl must do its own equivalent so the
    // `Command::new(tool)` probes below don't spuriously fail.
    if let Ok(home) = std::env::var("HOME") {
        let shims = format!("{home}/.local/share/mise/shims");
        if Path::new(&shims).is_dir() {
            let current = std::env::var("PATH").unwrap_or_default();
            if !current.split(':').any(|p| p == shims) {
                std::env::set_var("PATH", format!("{shims}:{current}"));
            }
        }
    }

    // External-service checks (brew bundle/doctor, gh auth, mise doctor,
    // claude doctor) shell out to network- and lock-bound tools that are slow
    // (brew bundle alone is ~15s) and can hang (Homebrew's global update lock,
    // MCP probes). Valuable in an interactive audit, but they make `doctor`
    // non-hermetic — unfit for the drift integration tests and far too heavy /
    // flaky for a per-push gate. DOTCTL_DOCTOR_SKIP_EXTERNAL=1 skips them; the
    // fast structural checks (git identity, tool presence, symlinks, drift,
    // mise ls, pueue) still run. Set by the doctor_drift tests and the
    // lefthook pre-push `doctor` command; unset for interactive `dotctl doctor`.
    let skip_external = std::env::var_os("DOTCTL_DOCTOR_SKIP_EXTERNAL").is_some();

    println!("==> Doctor");

    // ── Git config ───────────────────────────────────────────────────
    let user_name = capture("git", &["config", "user.name"]);
    let user_email = capture("git", &["config", "user.email"]);
    if !user_name.is_empty() && !user_email.is_empty() {
        ok(&format!("git: {user_name} <{user_email}>"));
    } else {
        fail("git: missing user.name or user.email");
        fails += 1;
    }

    // ── Tool presence ────────────────────────────────────────────────
    // Required tools hard-fail (exit 1); optional tools only warn. ghostty is
    // optional: its shim points at /Applications/Ghostty.app, which a user may
    // have removed deliberately (e.g. trialling gnar-term). A missing GUI
    // terminal shouldn't block the pre-push gate — surface it as a warning so
    // `dotctl doctor` still notes the drift without failing.
    let os = std::env::consts::OS;
    let mut tools: Vec<&str> = vec!["dotctl", "git", "gh", "mise"];
    let mut optional: Vec<&str> = Vec::new();
    if os == "macos" {
        tools.extend(["brew", "node", "bun", "sheldon", "lefthook", "hx"]);
        optional.push("ghostty");
    }
    for tool in &tools {
        let ver = capture(tool, &["--version"]);
        if !ver.is_empty() {
            // Trim multi-line versions to first line.
            ok(&format!("{tool}: {}", ver.lines().next().unwrap_or("")));
        } else {
            fail(&format!("{tool}: not found"));
            fails += 1;
        }
    }
    for tool in &optional {
        let ver = capture(tool, &["--version"]);
        if !ver.is_empty() {
            ok(&format!("{tool}: {}", ver.lines().next().unwrap_or("")));
        } else {
            warn_msg(&format!("{tool}: not found (optional)"));
            warns += 1;
        }
    }

    // ── Symlink integrity ────────────────────────────────────────────
    let home = std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("."));
    // $DOTFILES_DIR → path dotctl was built from → legacy ~/dotFiles.
    let dotfiles = crate::util::resolve_dotfiles_dir().unwrap_or_else(|| {
        warn_msg("dotfiles repo not found ($DOTFILES_DIR / built-from path / ~/dotFiles) — symlink + drift audits will be skipped");
        warns += 1;
        home.join("dotFiles")
    });
    let expected: &[(&str, &str)] = &[
        (".zshrc", ".zshrc"),
        (".zprofile", ".zprofile"),
        (".zshenv", ".zshenv"),
        (".gitconfig", ".gitconfig"),
        (".gitmessage", ".gitmessage"),
        (".ripgreprc", ".ripgreprc"),
        (".fdignore", ".fdignore"),
        (".editorconfig", ".editorconfig"),
        (".claude/CLAUDE.md", "dot-claude/CLAUDE.md"),
        (".claude/settings.json", "dot-claude/settings.json"),
        (".claude/agents", "dot-claude/agents"),
        (".claude/commands", "dot-claude/commands"),
        (".config/sheldon/plugins.toml", "sheldon/plugins.toml"),
        (".config/mise/config.toml", "mise.toml"),
        (".config/gh/config.yml", "gh/config.yml"),
        (".config/ghostty/config", "ghostty/config"),
        (".config/bat/config", "bat/config"),
        (".config/atuin/config.toml", "atuin/config.toml"),
        (".config/lazygit/config.yml", "lazygit/config.yml"),
        (".config/helix/languages.toml", "helix/languages.toml"),
        (".config/karabiner/karabiner.json", "karabiner/karabiner.json"),
        (".ssh/config", "ssh/config"),
    ];
    for (link_rel, target_rel) in expected {
        let link = home.join(link_rel);
        let expected_target = dotfiles.join(target_rel);
        if !target_exists(&expected_target) {
            // Source isn't tracked — skip silently (e.g., dropped tool).
            continue;
        }
        match std::fs::symlink_metadata(&link) {
            Err(_) => {
                warn_msg(&format!("symlink missing: {} (expected -> {})", link.display(), expected_target.display()));
                warns += 1;
            }
            Ok(m) if !m.file_type().is_symlink() => {
                warn_msg(&format!("{} is not a symlink (expected -> {})", link.display(), expected_target.display()));
                warns += 1;
            }
            Ok(_) => match std::fs::read_link(&link) {
                Ok(t) if t == expected_target => {
                    // Silently pass — too noisy to print every passing symlink.
                }
                Ok(t) => {
                    warn_msg(&format!(
                        "{} points to {}, expected {}",
                        link.display(),
                        t.display(),
                        expected_target.display()
                    ));
                    warns += 1;
                }
                Err(_) => {}
            },
        }
    }
    ok(&format!("symlinks: {} checked", expected.len()));

    // ── Doc drift scan ───────────────────────────────────────────────
    // Greps tracked config + code files for known-dead references. Top-level
    // CLAUDE.md / README.md are intentionally excluded — they describe the
    // migration history and will contain mentions like "There is no sync.sh."
    let drift_warns = scan_drift(&dotfiles);
    if drift_warns == 0 {
        ok("doc drift: no dead references in tracked configs");
    } else {
        // Per-line warnings printed inside scan_drift; just bump the counter.
        warns += drift_warns;
    }

    // ── brew bundle drift (Darwin) ───────────────────────────────────
    // Brewfile holds `brew "mise"` + casks under Lean A. `brew bundle check`
    // exits nonzero when any declared formula/cask is missing.
    //
    // --no-upgrade matches `step_brew`'s install flag in sync.rs — without
    // it, `check` flags packages with available updates as "drift," which
    // misaligns with sync (which only upgrades on --upgrade). The user
    // upgrades via `dotctl update`.
    #[cfg(target_os = "macos")]
    if !skip_external {
        let brewfile = dotfiles.join("Brewfile");
        if brewfile.is_file() {
            let status = Command::new("brew")
                .arg("bundle")
                .arg("check")
                .arg("--no-upgrade")
                .arg("--file")
                .arg(&brewfile)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            match status {
                Ok(s) if s.success() => ok("brew bundle: all dependencies satisfied"),
                Ok(_) => {
                    warn_msg("brew bundle: drift — run `brew bundle --file=~/dotFiles/Brewfile`");
                    warns += 1;
                }
                Err(_) => {} // brew missing — already flagged by tool-presence section
            }
        }
    }

    // ── gh auth status ───────────────────────────────────────────────
    // Several integrations depend on the keychain-stored token:
    // GITHUB_PERSONAL_ACCESS_TOKEN (zsh/00-exports.zsh), git_data PR
    // status (gh pr status). Surface unauth here so it doesn't manifest
    // as silent prompt degradation.
    if !skip_external {
        let status = Command::new("gh")
            .args(["auth", "status"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        match status {
            Ok(s) if s.success() => ok("gh: authenticated"),
            _ => {
                warn_msg("gh: not authenticated — run `gh auth login`");
                warns += 1;
            }
        }
    }

    // ── mise tools installed ────────────────────────────────────────
    // `mise ls --missing` lists declared tools that aren't installed.
    // Empty = all good; any output = drift.
    {
        let out = Command::new("mise").args(["ls", "--missing"]).output();
        if let Ok(o) = out {
            if o.status.success() {
                let s = String::from_utf8_lossy(&o.stdout);
                let missing: Vec<&str> = s.lines().filter(|l| !l.trim().is_empty()).collect();
                if missing.is_empty() {
                    ok("mise: all declared tools installed");
                } else {
                    warn_msg(&format!(
                        "mise: {} tool(s) missing — run `mise install`",
                        missing.len()
                    ));
                    for line in missing.iter().take(5) {
                        warn_msg(&format!("  {line}"));
                    }
                    warns += missing.len() as u32;
                }
            }
        }
    }

    // ── lefthook hook installed in this repo ─────────────────────────
    // dotctl sync runs `lefthook install`, but if a user runs commands in
    // a fresh worktree without syncing, the .git/hooks/pre-commit may not
    // exist. Catches that drift.
    {
        let lefthook_hook = dotfiles.join(".git/hooks/pre-commit");
        if !lefthook_hook.is_file() {
            warn_msg("lefthook: pre-commit hook not installed in dotfiles repo — run `lefthook install`");
            warns += 1;
        } else if let Ok(content) = fs::read_to_string(&lefthook_hook) {
            if content.contains("lefthook") {
                ok("lefthook: pre-commit hook installed");
            } else {
                warn_msg("lefthook: pre-commit hook present but not authored by lefthook — run `lefthook install`");
                warns += 1;
            }
        }
    }

    // ── pueued daemon liveness ───────────────────────────────────────
    // 80-functions.zsh auto-starts the daemon, but only on interactive
    // shells. A long-lived ssh session or a tmux pane spawned before the
    // auto-start was added can still have a stopped daemon.
    {
        let pueued_present = Command::new("pueued")
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if pueued_present {
            let status = Command::new("pueue")
                .arg("status")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            match status {
                Ok(s) if s.success() => ok("pueued: daemon responding"),
                _ => {
                    warn_msg("pueued: daemon not running — start with `pueued -d`");
                    warns += 1;
                }
            }
        }
    }

    // ── brew doctor (Darwin) ─────────────────────────────────────────
    // Absorbs `brew doctor` so users get a single audit entrypoint.
    // brew doctor exits 0 even with warnings; the heuristic for "clean"
    // is the "ready to brew" string in stdout/stderr.
    #[cfg(target_os = "macos")]
    if !skip_external {
        let out = Command::new("brew").arg("doctor").output();
        if let Ok(o) = out {
            let combined = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            if combined.contains("ready to brew") {
                ok("brew doctor: ready to brew");
            } else {
                let warning_lines: Vec<&str> = combined
                    .lines()
                    .filter(|l| l.trim_start().starts_with("Warning:"))
                    .collect();
                let n = warning_lines.len().max(1) as u32;
                warn_msg(&format!(
                    "brew doctor: {n} warning(s) — run `brew doctor` for details"
                ));
                for line in warning_lines.iter().take(3) {
                    warn_msg(&format!("  {}", line.trim()));
                }
                warns += n;
            }
        }
    }

    // ── mise doctor ──────────────────────────────────────────────────
    // mise doctor exits 0 even with warnings; "No problems found" is the
    // clean signal. Common warnings: version-upgrade-available (resolved
    // by `dotctl update`), untrusted config paths.
    //
    // We temporarily strip the shims-prepend from PATH for this single
    // subprocess. Otherwise mise raises "mise tool paths are not first in
    // PATH" — which is true (we put shims first deliberately for our own
    // tool probes earlier) but irrelevant to whether the user's *shell*
    // setup is healthy. Stripping just for this call lets mise audit the
    // shell-equivalent PATH.
    if !skip_external {
        let saved_path = std::env::var("PATH").ok();
        if let (Ok(home), Some(path)) = (std::env::var("HOME"), saved_path.as_ref()) {
            let shims_prefix = format!("{home}/.local/share/mise/shims:");
            if let Some(stripped) = path.strip_prefix(&shims_prefix) {
                std::env::set_var("PATH", stripped);
            }
        }

        let out = Command::new("mise").arg("doctor").output();

        if let Some(p) = saved_path {
            std::env::set_var("PATH", p);
        }

        if let Ok(o) = out {
            let combined = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            let n = parse_mise_warnings(&combined);
            if n == 0 && combined.contains("No problems found") {
                ok("mise doctor: no problems found");
            } else if n > 0 {
                warn_msg(&format!(
                    "mise doctor: {n} warning(s) — run `mise doctor` for details"
                ));
                warns += n;
            } else {
                // Couldn't parse — surface as a single warning rather than
                // silently swallowing.
                warn_msg("mise doctor: output unparseable — run `mise doctor` manually");
                warns += 1;
            }
        }
    }

    // ── claude doctor ────────────────────────────────────────────────
    // Surfaces Claude Code's own health check (auto-updater + MCP server
    // probes). claude doctor spawns the stdio MCP servers declared in
    // .mcp.json to probe them; if any block, this step hangs. No timeout
    // by design — a hang here means an MCP server is broken and should
    // be diagnosed, not hidden.
    if !skip_external && !capture("claude", &["--version"]).is_empty() {
        let out = Command::new("claude").arg("doctor").output();
        match out {
            Ok(o) if o.status.success() => {
                ok("claude doctor: healthy");
            }
            Ok(o) => {
                let combined = format!(
                    "{}{}",
                    String::from_utf8_lossy(&o.stdout),
                    String::from_utf8_lossy(&o.stderr)
                );
                fail(&format!(
                    "claude doctor: exit {} — output below",
                    o.status.code().unwrap_or(-1)
                ));
                for line in combined.lines().take(20) {
                    eprintln!("  {line}");
                }
                fails += 1;
            }
            Err(e) => {
                fail(&format!("claude doctor: spawn failed: {e}"));
                fails += 1;
            }
        }
    }

    // ── macOS defaults drift ─────────────────────────────────────────
    // Only runs on Darwin. Audits each MANAGED default via `defaults read`
    // and flags drift (the user changed it via System Settings) or missing
    // (never been applied — likely a fresh machine that hasn't synced yet).
    #[cfg(target_os = "macos")]
    {
        use crate::macos_defaults::{audit, AuditResult};
        let host = crate::host::current();
        let results = audit(host);
        let mut matches = 0usize;
        let mut drifted = 0usize;
        let mut missing = 0usize;
        for (d, result) in &results {
            match result {
                AuditResult::Match => matches += 1,
                AuditResult::Drift { expected, actual } => {
                    warn_msg(&format!(
                        "macos: {}.{} = {} (expected {})",
                        d.domain, d.key, actual, expected
                    ));
                    drifted += 1;
                    warns += 1;
                }
                AuditResult::Missing => {
                    warn_msg(&format!(
                        "macos: {}.{} unset (run `dotctl sync --only=macos`)",
                        d.domain, d.key
                    ));
                    missing += 1;
                    warns += 1;
                }
            }
        }
        ok(&format!(
            "macos defaults: {matches} matched, {drifted} drifted, {missing} missing"
        ));
    }

    // ── Summary ──────────────────────────────────────────────────────
    println!();
    if fails == 0 && warns == 0 {
        ok("All checks passed");
    } else if fails == 0 {
        warn_msg(&format!("{warns} warning(s) — see above"));
    } else {
        fail(&format!("{fails} error(s), {warns} warning(s)"));
        std::process::exit(1);
    }
    Ok(())
}

fn target_exists(p: &Path) -> bool {
    std::fs::symlink_metadata(p).is_ok()
}

// Parse `mise doctor` output for the leading number in "<n> warning(s)
// found". Returns 0 when not present (clean output or unrecognized form).
fn parse_mise_warnings(text: &str) -> u32 {
    for line in text.lines() {
        let trimmed = line.trim();
        // Match shapes like "1 warning found:" / "5 warnings found:".
        if let Some(rest) = trimmed.strip_suffix(":") {
            if let Some(num) = rest.strip_suffix(" warnings found")
                .or_else(|| rest.strip_suffix(" warning found"))
            {
                if let Ok(n) = num.trim().parse::<u32>() {
                    return n;
                }
            }
        }
    }
    0
}

// Dead-string scanner. Returns warning count. Each finding is printed with
// file:line context. Allowlist comments — a line containing
// `dotctl-drift-allow` is skipped, so deliberate historical references in
// config files can still mention the old path.
//
// Scope is fixed to config/code files; CLAUDE.md and README.md are excluded
// (they're the documentation about migration history). The `.rs` files in
// dotctl/src/ are also excluded because comments there reference the bash
// modules they replaced ("Rust port of sync.sh").
fn scan_drift(dotfiles: &Path) -> u32 {
    let dead_strings: &[&str] = &[
        "sync.sh",
        "scripts/theme.sh",
        "scripts/git-data.sh",
        "install/lib.sh",
        "install/00-",
        "starship",
        "AstroNvim",
        "nvim/lua",
    ];

    let mut files: Vec<PathBuf> = Vec::new();
    let strict: &[&str] = &[
        "lefthook.yml",
        "Makefile",
        "bootstrap.sh",
        "Brewfile",
        "mise.toml",
        ".zshrc",
        ".zprofile",
        ".zshenv",
        "dot-claude/settings.json",
        "dot-claude/CLAUDE.md",
        "atuin/config.toml",
        "bat/config",
        "gh/config.yml",
        "ghostty/config",
        "lazygit/config.yml",
        "sheldon/plugins.toml",
        "ssh/config",
    ];
    for f in strict {
        let p = dotfiles.join(f);
        if p.is_file() {
            files.push(p);
        }
    }
    for dir in ["zsh", "dot-claude/agents", "dot-claude/commands", "git-template/hooks"] {
        if let Ok(entries) = fs::read_dir(dotfiles.join(dir)) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_file() {
                    files.push(p);
                }
            }
        }
    }

    let mut warnings = 0u32;
    for path in &files {
        let Ok(content) = fs::read_to_string(path) else {
            continue;
        };
        for (idx, line) in content.lines().enumerate() {
            if line.contains("dotctl-drift-allow") {
                continue;
            }
            for dead in dead_strings {
                if line.contains(dead) {
                    let rel = path.strip_prefix(dotfiles).unwrap_or(path);
                    warn_msg(&format!(
                        "drift: {} L{}: \"{}\" found in `{}`",
                        rel.display(),
                        idx + 1,
                        dead,
                        line.trim()
                    ));
                    warnings += 1;
                }
            }
        }
    }
    warnings
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn write(dir: &std::path::Path, rel: &str, body: &str) {
        let p = dir.join(rel);
        if let Some(parent) = p.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(p, body).unwrap();
    }

    #[test]
    fn parse_mise_warnings_zero_on_clean() {
        assert_eq!(parse_mise_warnings("No problems found"), 0);
        assert_eq!(parse_mise_warnings(""), 0);
    }

    #[test]
    fn parse_mise_warnings_singular() {
        let s = "settings: ...\nmise WARN  mise version 2026.5.11 available\n\n1 warning found:\n\n1. new mise version available\n";
        assert_eq!(parse_mise_warnings(s), 1);
    }

    #[test]
    fn parse_mise_warnings_plural() {
        let s = "5 warnings found:\n\n1. foo\n2. bar\n";
        assert_eq!(parse_mise_warnings(s), 5);
    }

    #[test]
    fn parse_mise_warnings_ignores_unrelated_colons() {
        let s = "settings:\n  trusted_config_paths: ~\n";
        assert_eq!(parse_mise_warnings(s), 0);
    }

    #[test]
    fn scan_drift_empty_dotfiles_returns_zero() {
        let tmp = TempDir::new().unwrap();
        assert_eq!(scan_drift(tmp.path()), 0);
    }

    #[test]
    fn scan_drift_clean_files_returns_zero() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "lefthook.yml", "pre-push:\n  commands:\n    doctor:\n      run: dotctl doctor\n");
        write(tmp.path(), "Makefile", "sync:\n\tdotctl sync\n");
        write(tmp.path(), "zsh/00-exports.zsh", "export EDITOR=hx\n");
        assert_eq!(scan_drift(tmp.path()), 0);
    }

    #[test]
    fn scan_drift_finds_sync_sh_in_lefthook() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "lefthook.yml", "pre-push:\n  commands:\n    h:\n      run: ./sync.sh --only=health\n");
        assert_eq!(scan_drift(tmp.path()), 1);
    }

    #[test]
    fn scan_drift_finds_starship_in_zshrc() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), ".zshrc", "eval \"$(starship init zsh)\"\n");
        assert_eq!(scan_drift(tmp.path()), 1);
    }

    #[test]
    fn scan_drift_finds_astronvim_in_zsh_fragment() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "zsh/60-tools.zsh", "# AstroNvim viewer mode\nalias v=hx\n");
        assert_eq!(scan_drift(tmp.path()), 1);
    }

    #[test]
    fn scan_drift_allow_marker_skips_line() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "Makefile", "# legacy: sync.sh  # dotctl-drift-allow\n");
        assert_eq!(scan_drift(tmp.path()), 0);
    }

    #[test]
    fn scan_drift_counts_multiple_findings() {
        let tmp = TempDir::new().unwrap();
        write(
            tmp.path(),
            "Makefile",
            "a: sync.sh\nb: scripts/theme.sh\nc: starship\nd: AstroNvim\n",
        );
        assert_eq!(scan_drift(tmp.path()), 4);
    }

    #[test]
    fn scan_drift_skips_top_level_docs() {
        // README.md and CLAUDE.md (top-level) intentionally narrate history.
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "README.md", "There is no sync.sh anymore.\n");
        write(tmp.path(), "CLAUDE.md", "scripts/theme.sh is gone; AstroNvim removed.\n");
        assert_eq!(scan_drift(tmp.path()), 0);
    }

    #[test]
    fn scan_drift_includes_dot_claude_agents_and_commands() {
        let tmp = TempDir::new().unwrap();
        write(tmp.path(), "dot-claude/agents/foo.md", "Read scripts/git-data.sh.\n");
        write(tmp.path(), "dot-claude/commands/bar.md", "Run ./sync.sh --only=health\n");
        assert_eq!(scan_drift(tmp.path()), 2);
    }

    #[test]
    fn scan_drift_does_not_scan_dotctl_rs_sources() {
        // Rust comments reference historical paths (`Rust port of sync.sh`);
        // those mentions are by design and should never trigger the scan.
        let tmp = TempDir::new().unwrap();
        write(
            tmp.path(),
            "dotctl/src/sync.rs",
            "// Rust port of sync.sh + install/*.sh.\nfn main() {}\n",
        );
        assert_eq!(scan_drift(tmp.path()), 0);
    }
}

fn capture(prog: &str, args: &[&str]) -> String {
    Command::new(prog)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn ok(msg: &str) {
    println!("{GREEN}  ✓ {msg}{NC}");
}
fn warn_msg(msg: &str) {
    println!("{YELLOW}  → {msg}{NC}");
}
fn fail(msg: &str) {
    eprintln!("{RED}  ✗ {msg}{NC}");
}
