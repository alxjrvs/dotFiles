// util — shared helpers used by more than one subcommand module.
//
// Add helpers here when a second module would otherwise duplicate the
// implementation. Keep this module narrow: no business logic, no
// subcommand-specific knowledge.

use std::process::{Command, Stdio};

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
}
