// Integration test for `dotctl prompt-render`. Sets up a fake git-data cache
// in a temp XDG_CACHE_HOME and asserts the rendered prompt contains expected
// tokens.

use std::io::Write;
use std::process::Command;
use tempfile::TempDir;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_dotctl")
}

// dotctl computes the cache path from the current git toplevel (or cwd
// outside a repo). For test isolation we cd into a tempdir that ISN'T a git
// repo, then write a cache file at the cwd-derived path before invoking the
// binary.
fn write_cache_for_cwd(xdg_cache: &std::path::Path, cwd: &std::path::Path, body: &str) {
    // Compute the cache path the same way dotctl does. Cheaper than a public
    // helper: replicate the SHA + truncation rule once and assert in tests.
    let key = cwd.to_string_lossy();
    let hash = sha256_hex(&key);
    let short = &hash[..12];
    let dir = xdg_cache.join("git-data");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(format!("{short}.sh"));
    let mut f = std::fs::File::create(path).unwrap();
    f.write_all(body.as_bytes()).unwrap();
}

fn sha256_hex(s: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    h.update(s.as_bytes());
    format!("{:x}", h.finalize())
}

#[test]
fn prompt_render_emits_cwd_when_no_repo_cache() {
    // No cache → render falls back to cwd display. The binary should exit 0
    // and emit *something* (the rendered prompt string).
    let xdg = TempDir::new().unwrap();
    let cwd = TempDir::new().unwrap();
    let out = Command::new(bin())
        .arg("prompt-render")
        .env("XDG_CACHE_HOME", xdg.path())
        .current_dir(cwd.path())
        .output()
        .unwrap();
    assert!(out.status.success(), "exit: {}", out.status);
    assert!(!out.stdout.is_empty(), "prompt-render produced no output");
}

#[test]
fn prompt_render_includes_repo_name_when_cache_has_one() {
    let xdg = TempDir::new().unwrap();
    let cwd = TempDir::new().unwrap();
    // Canonicalize cwd to match how dotctl will see it (`std::env::current_dir`
    // resolves macOS's /tmp → /private/tmp symlink, so we hash on the resolved
    // form). Without this the cache file lands under one hash and dotctl looks
    // under another.
    let canonical_cwd = std::fs::canonicalize(cwd.path()).unwrap();
    // Write a cache as if we were in a repo named "fakerepo" with a clean tree.
    let body = "\
GIT_IS_REPO='1'
GIT_REPO_NAME='fakerepo'
GIT_REPO_HTTPS='https://example.invalid/fakerepo'
GIT_BRANCH='main'
GIT_PR_STATUS='pass'
GIT_PR_URL='https://example.invalid/fakerepo/pull/1'
GIT_PR_NUMBER='1'
";
    write_cache_for_cwd(xdg.path(), &canonical_cwd, body);
    let out = Command::new(bin())
        .arg("prompt-render")
        .env("XDG_CACHE_HOME", xdg.path())
        .current_dir(&canonical_cwd)
        .output()
        .unwrap();
    assert!(out.status.success(), "exit: {}", out.status);
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("fakerepo"), "expected repo name in prompt: {s:?}");
    assert!(s.contains("main"), "expected branch name in prompt: {s:?}");
    // Clean tree → emits the ✓ pip.
    assert!(s.contains('\u{2713}'), "expected clean check pip: {s:?}");
}
