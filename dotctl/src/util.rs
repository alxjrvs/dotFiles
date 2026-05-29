// util — shared helpers used by more than one subcommand module.
//
// Add helpers here when a second module would otherwise duplicate the
// implementation. Keep this module narrow: no business logic, no
// subcommand-specific knowledge.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Resolve the dotfiles repo root.
///
/// Tries, in order, and returns the first candidate that is a directory
/// containing a `Brewfile` (the repo sentinel — matches the check in
/// `sync::Context_::new`):
///
/// 1. `$DOTFILES_DIR` — explicit override, always wins when valid.
/// 2. The path the binary was *built* from — `CARGO_MANIFEST_DIR/..`
///    (`.../dotFiles/dotctl` → `.../dotFiles`). `step_dotctl` reinstalls the
///    binary from `<repo>/dotctl` on every sync, so this self-heals after the
///    repo is relocated: the next sync bakes the new path in.
/// 3. Legacy `$HOME/dotFiles` — backward-compat for pre-relocation binaries
///    and the documented bootstrap default.
///
/// Returns `None` when no candidate resolves; callers own the error wording.
pub fn resolve_dotfiles_dir() -> Option<PathBuf> {
    resolve_dotfiles_dir_from(
        std::env::var_os("DOTFILES_DIR").map(PathBuf::from),
        Path::new(env!("CARGO_MANIFEST_DIR")).parent().map(PathBuf::from),
        std::env::var_os("HOME").map(|h| PathBuf::from(h).join("dotFiles")),
    )
}

/// Pure core of [`resolve_dotfiles_dir`], split out so the candidate ordering
/// is testable without mutating process env or depending on the compile-time
/// `CARGO_MANIFEST_DIR`. Returns the first candidate that is a directory
/// containing a `Brewfile`.
fn resolve_dotfiles_dir_from(
    env_dir: Option<PathBuf>,
    built_from: Option<PathBuf>,
    legacy: Option<PathBuf>,
) -> Option<PathBuf> {
    let valid = |p: PathBuf| (p.is_dir() && p.join("Brewfile").is_file()).then_some(p);
    env_dir
        .and_then(valid)
        .or_else(|| built_from.and_then(valid))
        .or_else(|| legacy.and_then(valid))
}

/// Check whether `bin` is invokable in the current PATH.
///
/// Tries `sh -c 'command -v <bin>'` first (no fork of the target binary on
/// the missing-binary path); falls back to spawning `<bin> --version` so
/// PATH-resolved wrappers and shims also resolve. Both branches discard
/// stdout/stderr.
pub fn which(bin: &str) -> bool {
    Command::new("sh")
        .arg("-c")
        .arg(format!("command -v {bin}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
        || Command::new(bin)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn which_returns_true_for_sh() {
        // /bin/sh exists on every POSIX system; the fallback path will catch
        // it even if `command -v` somehow doesn't.
        assert!(which("sh"));
    }

    #[test]
    fn which_returns_false_for_nonsense_binary() {
        assert!(!which("definitely-not-a-real-binary-name-xyz123"));
    }

    fn repo(parent: &std::path::Path, name: &str) -> PathBuf {
        let d = parent.join(name);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("Brewfile"), "# fake\n").unwrap();
        d
    }

    #[test]
    fn resolve_prefers_env_dir_over_built_from_and_legacy() {
        let tmp = tempfile::TempDir::new().unwrap();
        let env_d = repo(tmp.path(), "env");
        let built = repo(tmp.path(), "built");
        let legacy = repo(tmp.path(), "legacy");
        let got = resolve_dotfiles_dir_from(Some(env_d.clone()), Some(built), Some(legacy));
        assert_eq!(got, Some(env_d));
    }

    #[test]
    fn resolve_falls_through_to_built_from_when_env_invalid() {
        let tmp = tempfile::TempDir::new().unwrap();
        let built = repo(tmp.path(), "built");
        let legacy = repo(tmp.path(), "legacy");
        // env points at a dir with no Brewfile → rejected.
        let bad_env = tmp.path().join("no-brewfile");
        std::fs::create_dir_all(&bad_env).unwrap();
        let got = resolve_dotfiles_dir_from(Some(bad_env), Some(built.clone()), Some(legacy));
        assert_eq!(got, Some(built));
    }

    #[test]
    fn resolve_falls_through_to_legacy_when_env_and_built_absent() {
        let tmp = tempfile::TempDir::new().unwrap();
        let legacy = repo(tmp.path(), "legacy");
        let got = resolve_dotfiles_dir_from(None, None, Some(legacy.clone()));
        assert_eq!(got, Some(legacy));
    }

    #[test]
    fn resolve_returns_none_when_no_candidate_valid() {
        let tmp = tempfile::TempDir::new().unwrap();
        // A dir that exists but has no Brewfile is not a valid repo.
        let bare = tmp.path().join("bare");
        std::fs::create_dir_all(&bare).unwrap();
        let missing = tmp.path().join("does-not-exist");
        assert_eq!(resolve_dotfiles_dir_from(Some(bare), Some(missing), None), None);
        assert_eq!(resolve_dotfiles_dir_from(None, None, None), None);
    }
}
