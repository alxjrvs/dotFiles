// End-to-end test for `dotctl doctor`'s drift scan. Builds a fixture dotfiles
// directory with known-bad references and verifies doctor reports them.

use std::io::Write;
use std::process::Command;
use tempfile::TempDir;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_dotctl")
}

fn write_file(dir: &std::path::Path, rel: &str, body: &str) {
    let path = dir.join(rel);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }
    let mut f = std::fs::File::create(path).unwrap();
    f.write_all(body.as_bytes()).unwrap();
}

fn fixture_dotfiles() -> TempDir {
    let tmp = TempDir::new().unwrap();
    let p = tmp.path();
    // Minimum shape doctor expects: a Brewfile + a few config files.
    write_file(p, "Brewfile", "brew \"mise\"\n");
    write_file(p, "mise.toml", "[tools]\n");
    write_file(p, ".zshrc", "# loader\n");
    write_file(p, ".zprofile", "# login\n");
    write_file(p, ".zshenv", "# env\n");
    write_file(p, "lefthook.yml", "pre-commit: {}\n");
    write_file(p, "Makefile", "sync:\n\tdotctl sync\n");
    write_file(p, "bootstrap.sh", "#!/bin/bash\nexit 0\n");
    write_file(p, "dot-claude/settings.json", "{}\n");
    write_file(p, "dot-claude/CLAUDE.md", "# clean\n");
    write_file(p, "atuin/config.toml", "");
    write_file(p, "bat/config", "");
    write_file(p, "gh/config.yml", "");
    write_file(p, "ghostty/config", "");
    write_file(p, "lazygit/config.yml", "");
    write_file(p, "sheldon/plugins.toml", "");
    write_file(p, "ssh/config", "");
    write_file(p, "zsh/00-exports.zsh", "export X=1\n");
    write_file(p, "git-hooks/pre-commit", "#!/bin/sh\nexit 0\n");
    tmp
}

#[test]
fn doctor_clean_fixture_reports_no_drift() {
    let tmp = fixture_dotfiles();
    let out = Command::new(bin())
        .arg("doctor")
        .env("DOTFILES_DIR", tmp.path())
        .env("HOME", tmp.path())
        // Hermetic: skip brew/gh/network checks so the drift scan is tested in
        // isolation (otherwise they block on Homebrew's global update lock).
        .env("DOTCTL_DOCTOR_SKIP_EXTERNAL", "1")
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let combined = format!("{stdout}{stderr}");
    assert!(
        combined.contains("doc drift: no dead references"),
        "expected clean drift; got:\n{combined}"
    );
}

#[test]
fn doctor_detects_sync_sh_in_lefthook() {
    let tmp = fixture_dotfiles();
    // Inject the drift.
    write_file(
        tmp.path(),
        "lefthook.yml",
        "pre-push:\n  commands:\n    h:\n      run: ./sync.sh --only=health\n",
    );
    let out = Command::new(bin())
        .arg("doctor")
        .env("DOTFILES_DIR", tmp.path())
        .env("HOME", tmp.path())
        // Hermetic: skip brew/gh/network checks so the drift scan is tested in
        // isolation (otherwise they block on Homebrew's global update lock).
        .env("DOTCTL_DOCTOR_SKIP_EXTERNAL", "1")
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let combined = format!("{stdout}{stderr}");
    assert!(
        combined.contains("drift:") && combined.contains("sync.sh"),
        "expected drift warning for sync.sh; got:\n{combined}"
    );
}

#[test]
fn doctor_drift_allow_marker_silences_warning() {
    let tmp = fixture_dotfiles();
    write_file(
        tmp.path(),
        "Makefile",
        "# historical reference: sync.sh  # dotctl-drift-allow\nsync:\n\tdotctl sync\n",
    );
    let out = Command::new(bin())
        .arg("doctor")
        .env("DOTFILES_DIR", tmp.path())
        .env("HOME", tmp.path())
        // Hermetic: skip brew/gh/network checks so the drift scan is tested in
        // isolation (otherwise they block on Homebrew's global update lock).
        .env("DOTCTL_DOCTOR_SKIP_EXTERNAL", "1")
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let combined = format!("{stdout}{stderr}");
    assert!(
        combined.contains("doc drift: no dead references"),
        "expected drift-allow marker to silence; got:\n{combined}"
    );
}

// Regression guard for the deadlock that hung pre-push: with
// DOTCTL_DOCTOR_SKIP_EXTERNAL set, the network/lock-bound checks must NOT run,
// so doctor stays hermetic and fast. The drift scan still runs (asserted by
// the tests above, which all set the flag). If someone later forgets to gate a
// new external check, this catches it.
#[test]
fn doctor_skip_external_omits_brew_and_network_checks() {
    let tmp = fixture_dotfiles();
    let out = Command::new(bin())
        .arg("doctor")
        .env("DOTFILES_DIR", tmp.path())
        .env("HOME", tmp.path())
        .env("DOTCTL_DOCTOR_SKIP_EXTERNAL", "1")
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let combined = format!("{stdout}{stderr}");
    // Structural checks still ran...
    assert!(
        combined.contains("doc drift"),
        "drift scan should still run when external is skipped; got:\n{combined}"
    );
    // ...but the gated external checks did not. (Needles avoid the
    // tool-presence lines: "gh: gh version…" and "brew: Homebrew…" still
    // print — only the gated *audit* outputs below must be absent.)
    for needle in ["brew bundle", "brew doctor", "authenticated", "mise doctor", "claude doctor"] {
        assert!(
            !combined.contains(needle),
            "external check '{needle}' should be skipped under DOTCTL_DOCTOR_SKIP_EXTERNAL; got:\n{combined}"
        );
    }
}
