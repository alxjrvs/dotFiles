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
    // Hot-path timing instrumentation. Every Claude Code turn fires
    // session-start/user-prompt-submit/policy-guard at minimum; with 10
    // arms wired, attribution of p95 latency was opaque before this.
    // Cost: one Instant + one JSONL append per dispatch.
    let start = std::time::Instant::now();
    let result = dispatch(event);
    log_timing(event, start.elapsed().as_millis(), result.is_ok());
    result
}

fn dispatch(event: &str) -> Result<()> {
    match event {
        "lock-file-guard" => lock_file_guard(),
        "policy-guard" => policy_guard(),
        "format-on-save" => format_on_save(),
        "trim-bash-output" => trim_bash_output(),
        "user-prompt-submit" => user_prompt_submit(),
        "worktree-create" => worktree_create(),
        "worktree-remove" => worktree_remove(),
        other => {
            eprintln!("dotctl hook: unknown event '{other}'");
            std::process::exit(2);
        }
    }
}

fn log_timing(event: &str, elapsed_ms: u128, ok: bool) {
    let entry = json!({
        "ts": iso_utc_now(),
        "event": event,
        "elapsed_ms": elapsed_ms,
        "ok": ok,
    });
    append_jsonl(&home_path(".claude/state/hook-timings.jsonl"), &entry);
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

// Map a file extension to the formatters that should run, in order.
// Pure routing logic — pulled out so we can unit test the dispatch table
// without invoking the actual formatters.
fn formatters_for(ext: &str) -> &'static [&'static str] {
    match ext {
        "sh" => &["shfmt"],
        "ts" | "tsx" | "js" | "jsx" => &["prettier", "eslint"],
        "css" => &["prettier"],
        _ => &[],
    }
}

// Auto-format edited files. Routes on extension via `formatters_for`;
// missing formatters are no-ops. eslint emits its findings as
// additionalContext when it has output.
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

    for tool in formatters_for(ext) {
        if !which(tool) {
            continue;
        }
        match *tool {
            "shfmt" => {
                let _ = Command::new("shfmt").args(["-w", "-i", "2", &file_path]).status();
            }
            "prettier" => {
                let _ = Command::new("prettier").args(["--write", &file_path]).status();
            }
            "eslint" => {
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
            _ => {}
        }
    }
    Ok(())
}

// ---------------------------------------------- 4. trim-bash-output (PostToolUse)

// Trim oversized Bash stdout to save context tokens. User still sees full
// output in the UI; this only changes what Claude sees via updatedToolOutput.
// Spill the full Bash stdout to a per-session file under /tmp/claude/spills/
// so the model can `Read` it on demand without re-running the command.
// Returns the spill path on success, None on any IO failure (trimming
// still proceeds — spill is best-effort enrichment, not a correctness gate).
fn spill_bash_output(session: &str, stdout: &str) -> Option<std::path::PathBuf> {
    let session_dir = if session.is_empty() { "no-session".to_string() } else { session.to_string() };
    let dir = Path::new("/tmp/claude/spills").join(session_dir);
    std::fs::create_dir_all(&dir).ok()?;
    let ts_ms = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .ok()?
        .as_millis();
    let path = dir.join(format!("{ts_ms}.txt"));
    std::fs::write(&path, stdout).ok()?;
    Some(path)
}

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
    let session = str_at(&input, &["session_id"]);
    let spill_path = spill_bash_output(&session, &stdout);
    let spill_hint = spill_path
        .as_ref()
        .map(|p| format!(" — full output spilled to {}", p.display()))
        .unwrap_or_default();

    const HEAD_LINES: usize = 200;
    const TAIL_LINES: usize = 100;
    let lines: Vec<&str> = stdout.lines().collect();

    let trimmed = if lines.len() > HEAD_LINES + TAIL_LINES {
        let head = lines[..HEAD_LINES].join("\n");
        let tail = lines[lines.len() - TAIL_LINES..].join("\n");
        let elided = lines.len() - HEAD_LINES - TAIL_LINES;
        format!(
            "{head}\n... [trim-bash-output: elided {elided} lines / ~{kb}KB to save context{spill_hint}] ...\n{tail}",
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
            "{head_part}\n... [trim-bash-output: elided {elided} chars (single huge line){spill_hint}] ...\n{tail_part}",
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

// --------------------------------- 12. worktree-create (WorktreeCreate)

// Replaces CC's default `git worktree add <cwd>/.claude/worktrees/<n>`
// path with `~/.local/share/cc-worktrees/<repo-basename>/<n>`. This
// sidesteps the harness-injected `denyWithinAllow` patterns on
// `<cwd>/HEAD` / `<cwd>/objects` / `<cwd>/refs` that block `git commit`
// inside the default worktree path under CC v2.1.150 (see upstream
// issues #25896, #17374, #61909).
//
// Stdin JSON: {name, session_id, cwd, ...}. Stdout: absolute path of
// the created worktree (CC reads this verbatim). Non-zero exit aborts
// session creation in CC.
//
// Override the base via DOTCTL_WORKTREE_DIR env var.
fn worktree_create() -> Result<()> {
    use anyhow::Context;
    let input = read_stdin_json();
    let name = str_at(&input, &["name"]);
    let cwd = str_at(&input, &["cwd"]);
    if name.is_empty() {
        anyhow::bail!("worktree-create: missing `name` in stdin JSON");
    }
    if cwd.is_empty() {
        anyhow::bail!("worktree-create: missing `cwd` in stdin JSON");
    }
    let path = worktree_path(&cwd, &name);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("create_dir_all {}", parent.display()))?;
    }
    let branch = format!("claude/{name}");
    let base_ref = std::env::var("CLAUDE_CODE_BASE_REF").unwrap_or_else(|_| "HEAD".to_string());
    // Capture git's output. `git worktree add` emits "Preparing
    // worktree..." and "HEAD is now at..." to stdout; CC parses
    // OUR ENTIRE hook stdout as the worktree path, so any git stdout
    // contamination corrupts the parse and CC fails with "hook
    // returned a path that is not a directory".
    let output = Command::new("git")
        .current_dir(&cwd)
        .args([
            "worktree",
            "add",
            "-b",
            &branch,
            path.to_str().unwrap(),
            &base_ref,
        ])
        .output()
        .context("spawn `git worktree add`")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprintln!("git worktree add failed: {stderr}");
        anyhow::bail!(
            "git worktree add failed: exit {}",
            output.status.code().unwrap_or(-1)
        );
    }
    // ONLY our path on stdout — CC reads this verbatim.
    println!("{}", path.display());
    Ok(())
}

// Compute the relocated worktree path. Default base is
// `~/.local/share/cc-worktrees/<repo-basename>` so multiple repos with
// the same basename collide only on the basename (acceptable for one
// user). Override via DOTCTL_WORKTREE_DIR.
fn worktree_path(cwd: &str, name: &str) -> std::path::PathBuf {
    let repo_basename = Path::new(cwd)
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "unknown-repo".to_string());
    let base = std::env::var("DOTCTL_WORKTREE_DIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| home_path(".local/share/cc-worktrees"));
    base.join(repo_basename).join(name)
}

// --------------------------------- 13. worktree-remove (WorktreeRemove)

// Paired cleanup hook. CC calls this when a session exits or a
// subagent finishes. Best-effort: errors logged to stderr but the
// hook returns Ok so CC's cleanup path doesn't stall.
fn worktree_remove() -> Result<()> {
    let input = read_stdin_json();
    let path = str_at(&input, &["path"]);
    if path.is_empty() {
        return Ok(());
    }
    let _ = Command::new("git")
        .args(["worktree", "remove", "--force", &path])
        .status();
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
    fn worktree_path_uses_repo_basename_and_default_base() {
        let prior = std::env::var("DOTCTL_WORKTREE_DIR").ok();
        std::env::remove_var("DOTCTL_WORKTREE_DIR");
        let p = worktree_path("/Users/jarvis/Code/gnar-term", "feature-x");
        let s = p.to_string_lossy();
        assert!(s.ends_with("/cc-worktrees/gnar-term/feature-x"), "got: {s}");
        assert!(s.contains(".local/share/"), "got: {s}");
        if let Some(v) = prior {
            std::env::set_var("DOTCTL_WORKTREE_DIR", v);
        }
    }

    #[test]
    fn worktree_path_respects_env_override() {
        let prior = std::env::var("DOTCTL_WORKTREE_DIR").ok();
        std::env::set_var("DOTCTL_WORKTREE_DIR", "/tmp/my-trees");
        let p = worktree_path("/whatever/repo", "branch-name");
        assert_eq!(p, std::path::PathBuf::from("/tmp/my-trees/repo/branch-name"));
        match prior {
            Some(v) => std::env::set_var("DOTCTL_WORKTREE_DIR", v),
            None => std::env::remove_var("DOTCTL_WORKTREE_DIR"),
        }
    }

    #[test]
    fn worktree_path_falls_back_for_root_cwd() {
        let prior = std::env::var("DOTCTL_WORKTREE_DIR").ok();
        std::env::set_var("DOTCTL_WORKTREE_DIR", "/tmp/x");
        // file_name() returns None for "/" — should not panic.
        let p = worktree_path("/", "n");
        assert!(p.to_string_lossy().contains("unknown-repo"));
        match prior {
            Some(v) => std::env::set_var("DOTCTL_WORKTREE_DIR", v),
            None => std::env::remove_var("DOTCTL_WORKTREE_DIR"),
        }
    }

    #[test]
    fn formatters_for_routes_shell_to_shfmt() {
        assert_eq!(formatters_for("sh"), &["shfmt"]);
    }

    #[test]
    fn formatters_for_routes_ts_family_to_prettier_then_eslint() {
        for ext in ["ts", "tsx", "js", "jsx"] {
            assert_eq!(formatters_for(ext), &["prettier", "eslint"], "ext={ext}");
        }
    }

    #[test]
    fn formatters_for_routes_css_to_prettier_only() {
        assert_eq!(formatters_for("css"), &["prettier"]);
    }

    #[test]
    fn formatters_for_unknown_ext_returns_empty() {
        assert!(formatters_for("py").is_empty());
        assert!(formatters_for("").is_empty());
        assert!(formatters_for("rs").is_empty()); // rustfmt is project-local, not hook-driven
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
