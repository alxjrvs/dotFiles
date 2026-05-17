// doctor subcommand — read-only diagnostics.
//
// Replaces install/80-health.sh and adds drift detection (symlink integrity,
// dotctl version, tool presence). Read-only: never modifies state. Exits
// non-zero if any check fails so it can be used in CI / pre-flight scripts.

use anyhow::Result;
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
    let dotfiles = home.join("dotFiles");
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
        (".claude/statusline-command.sh", "dot-claude/statusline-command.sh"),
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
