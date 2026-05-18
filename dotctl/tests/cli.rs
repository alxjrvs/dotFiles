// Integration tests: exec the dotctl binary directly via the cargo-provided
// path (CARGO_BIN_EXE_dotctl). These exercise the CLI surface end-to-end.

use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_dotctl")
}

#[test]
fn version_prints_crate_version() {
    let out = Command::new(bin()).arg("--version").output().unwrap();
    assert!(out.status.success(), "--version exit: {}", out.status);
    let s = String::from_utf8_lossy(&out.stdout);
    assert!(s.contains("dotctl"), "stdout: {s:?}");
    assert!(s.contains("0.1.0"), "stdout: {s:?}");
}

#[test]
fn help_lists_all_subcommands() {
    let out = Command::new(bin()).arg("--help").output().unwrap();
    assert!(out.status.success());
    let s = String::from_utf8_lossy(&out.stdout);
    for sub in ["sync", "update", "doctor", "git-data", "prompt-render", "statusline", "hook"] {
        assert!(s.contains(sub), "expected `{sub}` in --help; got: {s}");
    }
}

#[test]
fn unknown_subcommand_exits_nonzero() {
    let out = Command::new(bin()).arg("not-a-subcommand").output().unwrap();
    assert!(!out.status.success());
}

#[test]
fn hook_unknown_event_exits_two() {
    let out = Command::new(bin()).args(["hook", "bogus-event"]).output().unwrap();
    assert_eq!(out.status.code(), Some(2));
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("unknown event"));
}
