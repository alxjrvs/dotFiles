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
    let os = std::env::consts::OS;
    let mut tools: Vec<&str> = vec!["dotctl", "git", "gh", "mise"];
    if os == "macos" {
        tools.extend(["brew", "node", "bun", "sheldon", "lefthook", "hx"]);
    }
    for tool in tools {
        let ver = capture(tool, &["--version"]);
        if !ver.is_empty() {
            // Trim multi-line versions to first line.
            let first = ver.lines().next().unwrap_or("");
            ok(&format!("{tool}: {first}"));
        } else {
            fail(&format!("{tool}: not found"));
            fails += 1;
        }
    }

    // ── Symlink integrity ────────────────────────────────────────────
    let home = std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("."));
    let dotfiles = std::env::var("DOTFILES_DIR")
        .map(PathBuf::from)
        .ok()
        .filter(|p| p.is_dir())
        .unwrap_or_else(|| home.join("dotFiles"));
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
    for dir in ["zsh", "dot-claude/agents", "dot-claude/commands", "git-hooks"] {
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
