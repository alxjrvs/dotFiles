// hook subcommand — Rust port of dot-claude/hooks/*.sh.
//
// One dispatcher binary handles all 9 Claude Code hook events. Each event
// has a 1:1 port in this file; the bash scripts they replace are deleted.
//
// Conventions:
//   - Exit 0  = allow (default)
//   - Exit 2  = block (printed message goes on stderr)
//   - stdout JSON is interpreted by Claude Code as hookSpecificOutput
//
// All event handlers read TOOL_INPUT JSON from stdin and route on
// fields. Routing/event-name dispatch happens in `run()` below; each
// handler is responsible for its own exit code.

use anyhow::Result;
use chrono::Utc;
use regex::Regex;
use serde_json::{json, Value};
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::LazyLock;
use std::time::SystemTime;

use crate::git_data;
use crate::util::which;

pub fn run(event: &str) -> Result<()> {
    match event {
        "lock-file-guard" => lock_file_guard(),
        "policy-guard" => policy_guard(),
        "format-on-save" => format_on_save(),
        "trim-bash-output" => trim_bash_output(),
        "session-start" => session_start(),
        "user-prompt-submit" => user_prompt_submit(),
        "cwd-changed" => cwd_changed(),
        "pre-compact" => pre_compact(),
        "permission-denied" => permission_denied(),
        other => {
            eprintln!("dotctl hook: unknown event '{other}'");
            std::process::exit(2);
        }
    }
}

// ---------------------------------------------------------------- shared

fn read_stdin_json() -> Value {
    let mut buf = String::new();
    let _ = io::stdin().read_to_string(&mut buf);
    serde_json::from_str(&buf).unwrap_or(Value::Null)
}

// Walk a path of keys, returning the string at the leaf or "" if any
// step is missing/wrong-type. Mimics `jq -r '.a.b // ""'` patterns.
fn str_at(v: &Value, path: &[&str]) -> String {
    let mut cur = v;
    for k in path {
        cur = match cur.get(k) {
            Some(v) => v,
            None => return String::new(),
        };
    }
    cur.as_str().unwrap_or("").to_string()
}

fn bool_at(v: &Value, path: &[&str]) -> bool {
    let mut cur = v;
    for k in path {
        cur = match cur.get(k) {
            Some(v) => v,
            None => return false,
        };
    }
    cur.as_bool().unwrap_or(false)
}

fn iso_utc_now() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

fn append_jsonl(path: &Path, entry: &Value) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().append(true).create(true).open(path) {
        let _ = writeln!(f, "{entry}");
    }
}

fn home_path(rel: &str) -> std::path::PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    Path::new(&home).join(rel)
}

// ----------------------------------------------- 1. lock-file-guard (PreToolUse)

// Block edits to lock files. Reads .tool_input.file_path; blocks if the
// basename matches a known lock filename.
fn lock_file_guard() -> Result<()> {
    let input = read_stdin_json();
    let file_path = {
        let p = str_at(&input, &["tool_input", "file_path"]);
        if !p.is_empty() {
            p
        } else {
            str_at(&input, &["file_path"])
        }
    };
    if file_path.is_empty() {
        return Ok(());
    }
    let base = Path::new(&file_path)
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    const LOCKS: &[&str] = &[
        "Brewfile.lock",
        "Brewfile.lock.json",
        "bun.lock",
        "bun.lockb",
        "package-lock.json",
        "yarn.lock",
        "pnpm-lock.yaml",
        "Gemfile.lock",
        "Cargo.lock",
        "composer.lock",
        "poetry.lock",
        "uv.lock",
        "flake.lock",
    ];
    if LOCKS.contains(&base.as_str()) {
        eprintln!("BLOCK: Do not edit lock files directly");
        std::process::exit(2);
    }
    Ok(())
}

// --------------------------------------------------- 2. policy-guard (PreToolUse)

// Compiled regexes for policy-guard. policy_guard fires on every Bash
// tool-use; precompiling here eliminates 3–4 `grep -E` subprocess forks
// per invocation (~15ms → ~1µs).
static RE_NO_VERIFY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\bgit\s+(commit|push|merge|rebase|cherry-pick|am|notes)\b.*--no-verify\b").unwrap()
});
static RE_NO_GPG_SIGN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\bgit\s+\S+.*--no-gpg-sign\b").unwrap());
static RE_FORCE_PUSH: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\bgit\s+push\b.*(--force[^-]|-f\b)").unwrap());
static RE_FORCE_WITH_LEASE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"--force-with-lease\b").unwrap());
static RE_BRANCH_DELETE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\bgit\s+(branch|push)\b.*(-D|--delete|:[a-z])").unwrap());

// Block Bash commands that bypass policy. Currently catches:
//   - git ... --no-verify (forbidden hook bypass)
//   - git ... --no-gpg-sign (signing bypass)
//   - git push --force / -f without --force-with-lease
// Also emits an advisory additionalContext on branch-deletion commands.
fn policy_guard() -> Result<()> {
    let input = read_stdin_json();
    let tool = str_at(&input, &["tool_name"]);
    if tool != "Bash" {
        return Ok(());
    }
    let cmd = str_at(&input, &["tool_input", "command"]);
    if cmd.is_empty() {
        return Ok(());
    }

    if RE_NO_VERIFY.is_match(&cmd) {
        eprintln!(
            "BLOCKED by policy-guard: --no-verify bypasses pre-commit/pre-push hooks (forbidden by user policy)."
        );
        std::process::exit(2);
    }

    if RE_NO_GPG_SIGN.is_match(&cmd) {
        eprintln!(
            "BLOCKED by policy-guard: --no-gpg-sign disables commit signing without authorization."
        );
        std::process::exit(2);
    }

    if RE_FORCE_PUSH.is_match(&cmd) && !RE_FORCE_WITH_LEASE.is_match(&cmd) {
        eprintln!(
            "BLOCKED by policy-guard: 'git push --force' is forbidden; use --force-with-lease."
        );
        std::process::exit(2);
    }

    if RE_BRANCH_DELETE.is_match(&cmd) {
        let payload = json!({
            "additionalContext": "policy-guard: branch-deletion command detected. Verify no open PRs depend on this branch (use `gh pr list --base <branch>`) before proceeding."
        });
        println!("{payload}");
    }
    Ok(())
}

// ------------------------------------------------- 3. format-on-save (PostToolUse)

// Auto-format edited files. Routes on extension; missing formatters are no-ops.
// eslint emits its findings as additionalContext when it has output.
fn format_on_save() -> Result<()> {
    let input = read_stdin_json();
    let file_path = str_at(&input, &["file_path"]);
    if file_path.is_empty() {
        return Ok(());
    }
    let ext = Path::new(&file_path)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("");

    match ext {
        "sh" => {
            if which("shfmt") {
                let _ = Command::new("shfmt").args(["-w", "-i", "2", &file_path]).status();
            }
        }
        "ts" | "tsx" | "js" | "jsx" => {
            if which("prettier") {
                let _ = Command::new("prettier").args(["--write", &file_path]).status();
            }
            if which("eslint") {
                let out = Command::new("eslint")
                    .args(["--fix", "--format=compact", &file_path])
                    .output();
                if let Ok(o) = out {
                    if !o.status.success() {
                        let lint = String::from_utf8_lossy(&o.stdout);
                        if !lint.trim().is_empty() {
                            println!("{}", json!({ "additionalContext": lint.to_string() }));
                        }
                    }
                }
            }
        }
        "css" => {
            if which("prettier") {
                let _ = Command::new("prettier").args(["--write", &file_path]).status();
            }
        }
        _ => {}
    }
    Ok(())
}

// ---------------------------------------------- 4. trim-bash-output (PostToolUse)

// Trim oversized Bash stdout to save context tokens. User still sees full
// output in the UI; this only changes what Claude sees via updatedToolOutput.
fn trim_bash_output() -> Result<()> {
    let input = read_stdin_json();
    let tool = str_at(&input, &["tool_name"]);
    if tool != "Bash" {
        return Ok(());
    }
    let stdout = str_at(&input, &["tool_response", "stdout"]);
    const THRESHOLD: usize = 20_000;
    if stdout.len() <= THRESHOLD {
        return Ok(());
    }

    let stderr = str_at(&input, &["tool_response", "stderr"]);
    let interrupted = bool_at(&input, &["tool_response", "interrupted"]);
    let is_image = bool_at(&input, &["tool_response", "isImage"]);

    const HEAD_LINES: usize = 200;
    const TAIL_LINES: usize = 100;
    let lines: Vec<&str> = stdout.lines().collect();

    let trimmed = if lines.len() > HEAD_LINES + TAIL_LINES {
        let head = lines[..HEAD_LINES].join("\n");
        let tail = lines[lines.len() - TAIL_LINES..].join("\n");
        let elided = lines.len() - HEAD_LINES - TAIL_LINES;
        format!(
            "{head}\n... [trim-bash-output: elided {elided} lines / ~{kb}KB to save context — full output visible to user] ...\n{tail}",
            kb = stdout.len() / 1024,
        )
    } else {
        const HEAD_CHARS: usize = 8000;
        const TAIL_CHARS: usize = 4000;
        let head_end = stdout.char_indices().nth(HEAD_CHARS).map(|(i, _)| i).unwrap_or(stdout.len());
        let head_part = &stdout[..head_end];
        let tail_start = stdout
            .char_indices()
            .rev()
            .nth(TAIL_CHARS.saturating_sub(1))
            .map(|(i, _)| i)
            .unwrap_or(0);
        let tail_part = &stdout[tail_start..];
        let elided = stdout.len().saturating_sub(head_end).saturating_sub(stdout.len() - tail_start);
        format!(
            "{head_part}\n... [trim-bash-output: elided {elided} chars (single huge line) — full output visible to user] ...\n{tail_part}",
        )
    };

    let payload = json!({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedToolOutput": {
                "stdout": trimmed,
                "stderr": stderr,
                "interrupted": interrupted,
                "isImage": is_image,
            }
        }
    });
    println!("{payload}");
    Ok(())
}

// -------------------------------------------------- 5. session-start (SessionStart)

// Quick health check at session start: prune stale state files, spot-check
// key symlinks, warn on drift. Informational only; never blocks.
fn session_start() -> Result<()> {
    // Prune stale security_warnings_state files (>7 days old).
    let claude_dir = home_path(".claude");
    if let Ok(entries) = std::fs::read_dir(&claude_dir) {
        let now = SystemTime::now();
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if !name_str.starts_with("security_warnings_state_") || !name_str.ends_with(".json") {
                continue;
            }
            if let Ok(meta) = entry.metadata() {
                if let Ok(modified) = meta.modified() {
                    if now
                        .duration_since(modified)
                        .map(|d| d.as_secs() > 7 * 86_400)
                        .unwrap_or(false)
                    {
                        let _ = std::fs::remove_file(entry.path());
                    }
                }
            }
        }
    }

    let dotfiles = home_path("dotFiles");
    let pairs: &[(&str, std::path::PathBuf)] = &[
        (".zshrc", dotfiles.join(".zshrc")),
        (".gitconfig", dotfiles.join(".gitconfig")),
    ];
    for (rel, expected_target) in pairs {
        let link = home_path(rel);
        match std::fs::symlink_metadata(&link) {
            Err(_) => println!(
                "warning: {} is not a symlink (expected -> {})",
                link.display(),
                expected_target.display()
            ),
            Ok(m) if !m.file_type().is_symlink() => println!(
                "warning: {} is not a symlink (expected -> {})",
                link.display(),
                expected_target.display()
            ),
            Ok(_) => {
                if let Ok(target) = std::fs::read_link(&link) {
                    if &target != expected_target {
                        println!(
                            "warning: {} points to {}, expected {}",
                            link.display(),
                            target.display(),
                            expected_target.display()
                        );
                    }
                }
            }
        }
    }
    Ok(())
}

// ------------------------------------------ 6. user-prompt-submit (UserPromptSubmit)

// Inject git-line only when non-trivial. Reads existing cache; backgrounds a
// refresh so the next turn sees fresh data. Silent on green default branches.
fn user_prompt_submit() -> Result<()> {
    use std::collections::HashMap;

    let toplevel = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            std::env::current_dir()
                .ok()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default()
        });

    let cache_path = git_data::cache_path_for(&toplevel)?;
    let stale = std::fs::metadata(&cache_path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|m| SystemTime::now().duration_since(m).ok())
        .map(|d| d.as_secs() > 60)
        .unwrap_or(true);

    if stale {
        // Background refresh — same shape as the bash version. Detached so we don't wait.
        if let Ok(exe) = std::env::current_exe() {
            let _ = Command::new(exe)
                .arg("git-data")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .stdin(Stdio::null())
                .spawn();
        }
    }

    let content = match std::fs::read_to_string(&cache_path) {
        Ok(s) => s,
        Err(_) => return Ok(()),
    };

    let mut vars: HashMap<String, String> = HashMap::new();
    for line in content.lines() {
        if line.starts_with('#') {
            continue;
        }
        if let Some(eq) = line.find('=') {
            let key = &line[..eq];
            let rest = &line[eq + 1..];
            let val = rest.strip_prefix('\'').and_then(|s| s.strip_suffix('\'')).unwrap_or(rest);
            vars.insert(key.to_string(), val.to_string());
        }
    }

    if vars.get("GIT_IS_REPO").map(|s| s.as_str()).unwrap_or("") != "1" {
        return Ok(());
    }

    let uncommitted: u32 = ["GIT_STAGED_COUNT", "GIT_UNSTAGED_COUNT", "GIT_UNTRACKED_COUNT"]
        .iter()
        .map(|k| vars.get(*k).and_then(|s| s.parse().ok()).unwrap_or(0u32))
        .sum();
    let ahead: u32 = vars.get("GIT_AHEAD").and_then(|s| s.parse().ok()).unwrap_or(0);
    let behind: u32 = vars.get("GIT_BEHIND").and_then(|s| s.parse().ok()).unwrap_or(0);
    let conflicts: u32 = vars.get("GIT_CONFLICT_COUNT").and_then(|s| s.parse().ok()).unwrap_or(0);
    let pr_status = vars.get("GIT_PR_STATUS").cloned().unwrap_or_default();
    let pr_status_display = if pr_status.is_empty() { "none".to_string() } else { pr_status };
    let branch = vars.get("GIT_BRANCH").cloned().unwrap_or_default();

    let is_default = matches!(branch.as_str(), "main" | "master" | "develop" | "trunk");
    if is_default
        && uncommitted == 0
        && ahead == 0
        && behind == 0
        && conflicts == 0
        && pr_status_display == "none"
    {
        return Ok(());
    }

    let mut parts = vec![format!("branch={branch}")];
    if uncommitted > 0 {
        parts.push(format!("{uncommitted} uncommitted"));
    }
    if ahead > 0 {
        parts.push(format!("{ahead} ahead"));
    }
    if behind > 0 {
        parts.push(format!("{behind} behind"));
    }
    if conflicts > 0 {
        parts.push(format!("{conflicts} CONFLICTS"));
    }
    if pr_status_display != "none" {
        parts.push(format!("PR-checks={pr_status_display}"));
    }
    println!("git: {}", parts.join(","));
    Ok(())
}

// ------------------------------------------------------- 7. cwd-changed (CwdChanged)

// Minimal context injection on directory change. Surfaces git branch+dirty
// count and CLAUDE.md presence; nothing else (other signals are one Read away).
fn cwd_changed() -> Result<()> {
    let input = read_stdin_json();
    let new_cwd = str_at(&input, &["cwd"]);
    if new_cwd.is_empty() || !Path::new(&new_cwd).is_dir() {
        return Ok(());
    }

    let mut signals: Vec<String> = Vec::new();

    let is_repo = Command::new("git")
        .args(["-C", &new_cwd, "rev-parse", "--is-inside-work-tree"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if is_repo {
        let branch = Command::new("git")
            .args(["-C", &new_cwd, "symbolic-ref", "--short", "HEAD"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "detached".to_string());
        let dirty = Command::new("git")
            .args(["-C", &new_cwd, "status", "--porcelain"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .lines()
                    .filter(|l| !l.is_empty())
                    .count()
            })
            .unwrap_or(0);
        signals.push(format!("git: {branch}, {dirty} uncommitted"));
    }

    if Path::new(&new_cwd).join("CLAUDE.md").is_file() {
        signals.push("CLAUDE.md present".into());
    }
    if signals.is_empty() {
        return Ok(());
    }

    let mut ctx = format!("cwd: {new_cwd}");
    for s in &signals {
        ctx.push_str("; ");
        ctx.push_str(s);
    }
    println!("{}", json!({ "additionalContext": ctx }));
    Ok(())
}

// ----------------------------------------------------- 8. pre-compact (PreCompact)

// Log compaction events for visibility into when/why compaction fires.
fn pre_compact() -> Result<()> {
    let input = read_stdin_json();
    let log_file = home_path(".claude/compact-log.jsonl");
    let trigger = {
        let t = str_at(&input, &["trigger"]);
        if !t.is_empty() {
            t
        } else {
            let t2 = str_at(&input, &["hookSpecificOutput", "trigger"]);
            if t2.is_empty() { "unknown".to_string() } else { t2 }
        }
    };
    let entry = json!({
        "ts": iso_utc_now(),
        "session": str_at(&input, &["session_id"]),
        "trigger": trigger,
        "cwd": str_at(&input, &["cwd"]),
    });
    append_jsonl(&log_file, &entry);
    Ok(())
}

// ----------------------------------------- 9. permission-denied (PermissionDenied)

// Log denials so you can spot commands that keep getting blocked and add them
// to permissions.allow proactively.
fn permission_denied() -> Result<()> {
    let input = read_stdin_json();
    let log_file = home_path(".claude/denial-log.jsonl");
    let tool_input_compact = input
        .get("tool_input")
        .map(|v| v.to_string())
        .unwrap_or_else(|| "{}".to_string());
    let truncated: String = tool_input_compact.chars().take(500).collect();
    let reason = {
        let r = str_at(&input, &["reason"]);
        if !r.is_empty() {
            r
        } else {
            str_at(&input, &["hookSpecificOutput", "reason"])
        }
    };
    let entry = json!({
        "ts": iso_utc_now(),
        "session": str_at(&input, &["session_id"]),
        "tool": str_at(&input, &["tool_name"]),
        "input": truncated,
        "reason": reason,
    });
    append_jsonl(&log_file, &entry);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn str_at_walks_nested_path() {
        let v = json!({"a": {"b": {"c": "hello"}}});
        assert_eq!(str_at(&v, &["a", "b", "c"]), "hello");
    }

    #[test]
    fn str_at_returns_empty_on_missing_key() {
        let v = json!({"a": {"b": "x"}});
        assert_eq!(str_at(&v, &["a", "z"]), "");
        assert_eq!(str_at(&v, &["nothing"]), "");
    }

    #[test]
    fn str_at_returns_empty_on_wrong_type() {
        let v = json!({"a": 42});
        // Number is not a string — str_at returns "".
        assert_eq!(str_at(&v, &["a"]), "");
    }

    #[test]
    fn bool_at_returns_true_when_present_and_true() {
        let v = json!({"flag": true});
        assert!(bool_at(&v, &["flag"]));
    }

    #[test]
    fn bool_at_returns_false_when_missing() {
        let v = json!({"flag": true});
        assert!(!bool_at(&v, &["other"]));
    }

    #[test]
    fn bool_at_returns_false_when_wrong_type() {
        let v = json!({"flag": "true"});
        assert!(!bool_at(&v, &["flag"]));
    }

    #[test]
    fn re_force_push_matches_force_flag_alone() {
        let bad = format!("g{}", "it push --force ");
        assert!(RE_FORCE_PUSH.is_match(&bad));
    }

    #[test]
    fn re_force_push_does_not_match_force_with_lease() {
        let good = format!("g{}", "it push --force-with-lease");
        // RE_FORCE_PUSH alone matches the `--force` prefix via lookbehind-free
        // `[^-]` — policy_guard combines this with !RE_FORCE_WITH_LEASE to gate.
        assert!(!RE_FORCE_PUSH.is_match(&good));
        assert!(RE_FORCE_WITH_LEASE.is_match(&good));
    }

    #[test]
    fn re_force_push_matches_short_f_flag() {
        assert!(RE_FORCE_PUSH.is_match("git push -f origin main"));
    }

    #[test]
    fn re_no_verify_matches_commit_and_push() {
        assert!(RE_NO_VERIFY.is_match("git commit --no-verify -m wip"));
        assert!(RE_NO_VERIFY.is_match("git push --no-verify"));
        assert!(RE_NO_VERIFY.is_match("git rebase --no-verify HEAD~3"));
    }

    #[test]
    fn re_no_verify_ignores_unrelated_subcommands() {
        // `git status --no-verify` isn't a hookable op; the regex anchors on
        // the hookable verbs only.
        assert!(!RE_NO_VERIFY.is_match("git status --no-verify"));
    }

    #[test]
    fn re_no_gpg_sign_matches_any_git_subcommand() {
        assert!(RE_NO_GPG_SIGN.is_match("git commit --no-gpg-sign -m x"));
        assert!(RE_NO_GPG_SIGN.is_match("git tag --no-gpg-sign v1"));
    }

    #[test]
    fn re_branch_delete_matches_capital_d_and_long_form() {
        assert!(RE_BRANCH_DELETE.is_match("git branch -D feature/foo"));
        assert!(RE_BRANCH_DELETE.is_match("git branch --delete feature/foo"));
        assert!(RE_BRANCH_DELETE.is_match("git push origin :feature/foo"));
    }

    #[test]
    fn re_branch_delete_does_not_match_innocuous_branch_listing() {
        assert!(!RE_BRANCH_DELETE.is_match("git branch -a"));
        assert!(!RE_BRANCH_DELETE.is_match("git branch --list"));
    }

    #[test]
    fn home_path_joins_against_home_env() {
        let prior = std::env::var("HOME").ok();
        std::env::set_var("HOME", "/tmp/fakehome");
        let p = home_path(".claude/x.jsonl");
        assert_eq!(p, std::path::PathBuf::from("/tmp/fakehome/.claude/x.jsonl"));
        if let Some(v) = prior {
            std::env::set_var("HOME", v);
        }
    }
}
