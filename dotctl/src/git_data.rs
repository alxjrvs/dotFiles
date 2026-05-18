// git-data subcommand — Rust port of scripts/git-data.sh, with PR status.
//
// Gathers git state in a single pass and writes a shell-sourceable cache
// file at $XDG_CACHE_HOME/git-data/<repo-hash>.sh (mode 600, dir 700).
// Cache key is the repo toplevel (or cwd if outside a repo).
//
// Output format extends scripts/git-data.sh with PR-status fields. Existing
// zsh consumers (`source $cache_file`) work unchanged; the prompt's PR
// color cascade in zsh/50-prompt.zsh now lights up against real data.
//
// Variables emitted:
//   GIT_IS_REPO, GIT_IS_WORKTREE, GIT_WORKTREE_NAME, GIT_DIR,
//   GIT_TOPLEVEL, GIT_BRANCH, GIT_REMOTE_URL, GIT_REPO_NAME,
//   GIT_REPO_HTTPS, GIT_PORCELAIN, GIT_CONFLICT_COUNT, GIT_STAGED_COUNT,
//   GIT_UNSTAGED_COUNT, GIT_UNTRACKED_COUNT, GIT_STASH_COUNT,
//   GIT_AHEAD, GIT_BEHIND, GIT_CACHE_TIME,
//   GIT_PR_STATUS (pass|pending|fail|""), GIT_PR_URL, GIT_PR_NUMBER,
//   GIT_PR_CHECKED_AT

use anyhow::Result;
use chrono::{DateTime, Local};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Default)]
struct GitData {
    is_repo: bool,
    is_worktree: bool,
    worktree_name: String,
    git_dir: String,
    toplevel: String,
    branch: String,
    remote_url: String,
    repo_name: String,
    repo_https: String,
    porcelain: String,
    conflict_count: u32,
    staged_count: u32,
    unstaged_count: u32,
    untracked_count: u32,
    stash_count: u32,
    ahead: u32,
    behind: u32,
    pr_status: String,
    pr_url: String,
    pr_number: u32,
    pr_checked_at: u64,
}

// PR status freshness — gh costs ~1s per call. With 60s TTL we hit gh once
// per minute per repo, and the prompt/statusline pick up cached values
// instantly the rest of the time.
const PR_TTL_SECS: u64 = 60;

pub fn run() -> Result<()> {
    let mut data = gather();
    let cache_file = cache_path(&data.toplevel)?;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    // PR-status freshness: reuse cached values if checked within TTL.
    // Skipped entirely when not in a repo (gh would error anyway).
    if data.is_repo {
        match read_existing_pr_data(&cache_file).filter(|p| now.saturating_sub(p.3) < PR_TTL_SECS) {
            Some((status, url, number, checked_at)) => {
                data.pr_status = status;
                data.pr_url = url;
                data.pr_number = number;
                data.pr_checked_at = checked_at;
            }
            None => {
                let (status, url, number) = query_pr_status();
                data.pr_status = status;
                data.pr_url = url;
                data.pr_number = number;
                data.pr_checked_at = now;
            }
        }
    }

    write_cache(&cache_file, &data)?;
    Ok(())
}

// Read just the PR-status fields from a prior cache file, if present.
// Returns (status, url, number, checked_at). Returns None if the file
// is missing, unparsable, or doesn't carry PR fields yet (e.g. legacy
// bash-written caches from before PR support).
fn read_existing_pr_data(cache_file: &PathBuf) -> Option<(String, String, u32, u64)> {
    let content = fs::read_to_string(cache_file).ok()?;
    let mut status = None;
    let mut url = None;
    let mut number = None;
    let mut checked_at = None;
    for line in content.lines() {
        if let Some(v) = single_quoted_value(line, "GIT_PR_STATUS=") {
            status = Some(v.to_string());
        } else if let Some(v) = single_quoted_value(line, "GIT_PR_URL=") {
            url = Some(v.to_string());
        } else if let Some(v) = single_quoted_value(line, "GIT_PR_NUMBER=") {
            number = v.parse().ok();
        } else if let Some(v) = single_quoted_value(line, "GIT_PR_CHECKED_AT=") {
            checked_at = v.parse().ok();
        }
    }
    Some((status?, url?, number?, checked_at?))
}

// Extract the single-quoted value from a `KEY='value'` line. Inverse of the
// write-cache emission. Returns None if the prefix doesn't match or quotes
// are malformed.
fn single_quoted_value<'a>(line: &'a str, prefix: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(prefix)?;
    let inner = rest.strip_prefix('\'')?.strip_suffix('\'')?;
    Some(inner)
}

// Query gh for the current branch's PR status. Returns ("", "", 0) when
// no PR exists, gh is missing, or gh is unauthenticated. All gracefully
// degrades — the prompt cascade treats empty status as "no PR cell".
//
// We aggregate statusCheckRollup in jq to keep this binary dep-free:
//   - any check FAILURE                  → fail
//   - any check still running / no checks → pending
//   - all SUCCESS                        → pass
fn query_pr_status() -> (String, String, u32) {
    const JQ: &str = r#"
        if .currentBranch == null then "" else
            (.currentBranch.statusCheckRollup // []) as $checks |
            (if   ($checks | any(.conclusion == "FAILURE")) then "fail"
             elif ($checks | length == 0) then "pending"
             elif ($checks | any(.conclusion == null or .conclusion == "")) then "pending"
             else "pass" end) as $s |
            $s + "\t" + (.currentBranch.url // "") + "\t" + ((.currentBranch.number // 0) | tostring)
        end
    "#;
    let out = match Command::new("gh")
        .args(["pr", "status", "--json", "statusCheckRollup,number,url", "--jq", JQ])
        .output()
    {
        Ok(o) if o.status.success() => o.stdout,
        _ => return (String::new(), String::new(), 0),
    };
    let s = String::from_utf8_lossy(&out).trim().to_string();
    if s.is_empty() {
        return (String::new(), String::new(), 0);
    }
    let parts: Vec<&str> = s.split('\t').collect();
    if parts.len() != 3 {
        return (String::new(), String::new(), 0);
    }
    (
        parts[0].to_string(),
        parts[1].to_string(),
        parts[2].parse().unwrap_or(0),
    )
}

fn gather() -> GitData {
    let mut d = GitData::default();

    // git rev-parse --git-dir --git-common-dir --show-toplevel
    let rev = match git(&["rev-parse", "--git-dir", "--git-common-dir", "--show-toplevel"]) {
        Ok(s) => s,
        Err(_) => return d, // not a repo — defaults are fine
    };
    let lines: Vec<&str> = rev.lines().collect();
    if lines.len() < 3 {
        return d;
    }
    d.is_repo = true;
    d.git_dir = lines[0].to_string();
    let common_dir = lines[1];
    d.toplevel = lines[2].to_string();

    if d.git_dir != common_dir {
        d.is_worktree = true;
        d.worktree_name = std::path::Path::new(&d.toplevel)
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
    }

    // Single git call for branch + ahead/behind + porcelain.
    let status = git(&["status", "--porcelain=v2", "--branch", "--ahead-behind"]).unwrap_or_default();

    for line in status.lines() {
        if let Some(rest) = line.strip_prefix("# branch.head ") {
            d.branch = rest.to_string();
        } else if let Some(rest) = line.strip_prefix("# branch.ab ") {
            // Format: "+<ahead> -<behind>"
            let parts: Vec<&str> = rest.split_whitespace().collect();
            if parts.len() == 2 {
                d.ahead = parts[0].trim_start_matches('+').parse().unwrap_or(0);
                d.behind = parts[1].trim_start_matches('-').parse().unwrap_or(0);
            }
        }
    }

    // Detached HEAD fallback.
    if d.branch.is_empty() || d.branch == "(detached)" {
        if let Ok(short) = git(&["rev-parse", "--short", "HEAD"]) {
            d.branch = short.trim().to_string();
        }
    }

    // Remote URL → HTTPS + name.
    if let Ok(remote) = git(&["remote", "get-url", "origin"]) {
        let remote = remote.trim().to_string();
        if !remote.is_empty() {
            d.remote_url = remote.clone();
            d.repo_https = remote
                .replace("git@github.com:", "https://github.com/")
                .strip_suffix(".git")
                .map(String::from)
                .unwrap_or_else(|| {
                    remote
                        .replace("git@github.com:", "https://github.com/")
                        .to_string()
                });
            d.repo_name = std::path::Path::new(&d.repo_https)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default();
        }
    }

    // Parse porcelain entries into a v1-compatible representation, and
    // count conflicts / staged / unstaged / untracked in the same pass.
    let mut porcelain_lines: Vec<String> = Vec::new();
    for line in status.lines() {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        let bytes = line.as_bytes();
        let kind = bytes[0] as char;
        match kind {
            '1' => {
                // "1 XY ..." — ordinary change. Field 1 is the XY pair.
                let xy = &line[2..4];
                // Path is field 9 onward (1-indexed); easiest is split_whitespace + skip.
                if let Some(path) = extract_path_after_fields(line, 8) {
                    porcelain_lines.push(format!("{xy} {path}"));
                    tally(&mut d, xy);
                }
            }
            '2' => {
                // "2 XY ... path" — rename/copy. Field 10 is path (renamed).
                let xy = &line[2..4];
                if let Some(path) = extract_path_after_fields(line, 9) {
                    porcelain_lines.push(format!("{xy} {path}"));
                    tally(&mut d, xy);
                }
            }
            'u' => {
                // "u XY ..." — unmerged. Field 11 is path.
                let xy = &line[2..4];
                if let Some(path) = extract_path_after_fields(line, 10) {
                    porcelain_lines.push(format!("{xy} {path}"));
                    tally(&mut d, xy);
                }
            }
            '?' => {
                // "? path" — untracked. Path is bytes 2..
                let path = &line[2..];
                porcelain_lines.push(format!("?? {path}"));
                d.untracked_count += 1;
            }
            _ => {}
        }
    }
    d.porcelain = porcelain_lines.join("\n");

    // Stash count.
    if let Ok(stash) = git(&["stash", "list"]) {
        d.stash_count = stash.lines().filter(|l| !l.is_empty()).count() as u32;
    }

    d
}

// Extract the file path that follows `n` whitespace-separated fields at the
// start of the line. Used for porcelain v2 entry parsing where the path field
// position varies by entry kind (9/10/11).
fn extract_path_after_fields(line: &str, n: usize) -> Option<String> {
    let mut count = 0;
    let mut chars = line.char_indices();
    while let Some((i, c)) = chars.next() {
        if c.is_whitespace() {
            count += 1;
            if count == n {
                // Skip remaining whitespace, return rest of line.
                let rest = &line[i + 1..];
                return Some(rest.trim_start().to_string());
            }
        }
    }
    None
}

fn tally(d: &mut GitData, xy: &str) {
    let x = xy.chars().next().unwrap_or(' ');
    let y = xy.chars().nth(1).unwrap_or(' ');

    // Conflict patterns from porcelain v1: UU AA DD AU UA DU UD.
    let xy_combined = format!("{x}{y}");
    let is_conflict = matches!(xy_combined.as_str(), "UU" | "AA" | "DD" | "AU" | "UA" | "DU" | "UD");
    if is_conflict {
        d.conflict_count += 1;
        return;
    }

    if matches!(x, 'M' | 'A' | 'D' | 'R' | 'C') {
        d.staged_count += 1;
    }
    if matches!(y, 'M' | 'D') {
        d.unstaged_count += 1;
    }
}

fn git(args: &[&str]) -> Result<String> {
    let out = Command::new("git").args(args).output()?;
    if !out.status.success() {
        anyhow::bail!("git {args:?} exited {}", out.status);
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

// Public for hook::user_prompt_submit which needs to read the same cache
// file without re-running gather.
pub fn cache_path_for(toplevel: &str) -> Result<PathBuf> {
    cache_path(toplevel)
}

// Load the cache file into a plain HashMap<KEY, value>. Returns an empty
// map on any error (missing file, parse failure). Strips the `'...'`
// quoting from values. Skips comment lines.
pub fn load_cache() -> std::collections::HashMap<String, String> {
    use std::collections::HashMap;
    let toplevel = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    let cache_file = match cache_path_for(&toplevel) {
        Ok(p) => p,
        Err(_) => return HashMap::new(),
    };
    let content = match fs::read_to_string(&cache_file) {
        Ok(s) => s,
        Err(_) => return HashMap::new(),
    };
    let mut out = HashMap::new();
    for line in content.lines() {
        if line.starts_with('#') {
            continue;
        }
        if let Some(eq) = line.find('=') {
            let key = line[..eq].to_string();
            let rest = &line[eq + 1..];
            let val = rest
                .strip_prefix('\'')
                .and_then(|s| s.strip_suffix('\''))
                .unwrap_or(rest)
                .to_string();
            out.insert(key, val);
        }
    }
    out
}

fn cache_path(toplevel: &str) -> Result<PathBuf> {
    let key = if toplevel.is_empty() {
        std::env::current_dir()?.to_string_lossy().into_owned()
    } else {
        toplevel.to_string()
    };
    let mut hasher = Sha256::new();
    hasher.update(key.as_bytes());
    let hash = format!("{:x}", hasher.finalize());
    let short = &hash[..12];

    let cache_dir = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            PathBuf::from(home).join(".cache")
        })
        .join("git-data");

    fs::create_dir_all(&cache_dir)?;
    // Mode 700 — match the bash script.
    fs::set_permissions(&cache_dir, fs::Permissions::from_mode(0o700)).ok();

    Ok(cache_dir.join(format!("{short}.sh")))
}

fn write_cache(path: &PathBuf, d: &GitData) -> Result<()> {
    // Single-quoted escape: replace ' with '\''
    let esc = |s: &str| s.replace('\'', "'\\''");

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let now_human = format_human_time(now);

    let bool01 = |b: bool| if b { "1" } else { "" };

    let body = format!(
        "# git-data cache — generated by dotctl git-data\n\
         # Generated: {now_human}\n\
         GIT_CACHE_TIME='{now}'\n\
         GIT_IS_REPO='{is_repo}'\n\
         GIT_IS_WORKTREE='{is_worktree}'\n\
         GIT_WORKTREE_NAME='{worktree_name}'\n\
         GIT_DIR='{git_dir}'\n\
         GIT_TOPLEVEL='{toplevel}'\n\
         GIT_BRANCH='{branch}'\n\
         GIT_REMOTE_URL='{remote_url}'\n\
         GIT_REPO_NAME='{repo_name}'\n\
         GIT_REPO_HTTPS='{repo_https}'\n\
         GIT_PORCELAIN='{porcelain}'\n\
         GIT_CONFLICT_COUNT='{conflict_count}'\n\
         GIT_STAGED_COUNT='{staged_count}'\n\
         GIT_UNSTAGED_COUNT='{unstaged_count}'\n\
         GIT_UNTRACKED_COUNT='{untracked_count}'\n\
         GIT_STASH_COUNT='{stash_count}'\n\
         GIT_AHEAD='{ahead}'\n\
         GIT_BEHIND='{behind}'\n\
         GIT_PR_STATUS='{pr_status}'\n\
         GIT_PR_URL='{pr_url}'\n\
         GIT_PR_NUMBER='{pr_number}'\n\
         GIT_PR_CHECKED_AT='{pr_checked_at}'\n",
        is_repo = bool01(d.is_repo),
        is_worktree = bool01(d.is_worktree),
        worktree_name = esc(&d.worktree_name),
        git_dir = esc(&d.git_dir),
        toplevel = esc(&d.toplevel),
        branch = esc(&d.branch),
        remote_url = esc(&d.remote_url),
        repo_name = esc(&d.repo_name),
        repo_https = esc(&d.repo_https),
        porcelain = esc(&d.porcelain),
        conflict_count = d.conflict_count,
        staged_count = d.staged_count,
        unstaged_count = d.unstaged_count,
        untracked_count = d.untracked_count,
        stash_count = d.stash_count,
        ahead = d.ahead,
        behind = d.behind,
        pr_status = esc(&d.pr_status),
        pr_url = esc(&d.pr_url),
        pr_number = d.pr_number,
        pr_checked_at = d.pr_checked_at,
    );

    // Atomic write: tempfile in same dir, then rename. umask-equivalent: write
    // with mode 600 explicitly.
    let tmp = path.with_extension(format!("{}.tmp", std::process::id()));
    {
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&tmp)?;
        f.write_all(body.as_bytes())?;
    }
    fs::rename(&tmp, path).inspect_err(|_| {
        let _ = fs::remove_file(&tmp);
    })?;

    Ok(())
}

// Local-time human stamp for the cache header. Informational only; consumers
// don't parse it. Mirrors `date`'s default macOS format
// ("Sat May 17 14:30:12 PDT 2026") so existing cache-file readability is
// preserved across the chrono swap.
fn format_human_time(epoch_secs: u64) -> String {
    DateTime::from_timestamp(epoch_secs as i64, 0)
        .map(|dt| dt.with_timezone(&Local).format("%a %b %e %H:%M:%S %Z %Y").to_string())
        .unwrap_or_else(|| epoch_secs.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_quoted_value_extracts_simple_string() {
        assert_eq!(
            single_quoted_value("GIT_BRANCH='main'", "GIT_BRANCH="),
            Some("main")
        );
    }

    #[test]
    fn single_quoted_value_returns_none_on_wrong_prefix() {
        assert_eq!(
            single_quoted_value("GIT_BRANCH='main'", "GIT_OTHER="),
            None
        );
    }

    #[test]
    fn single_quoted_value_returns_none_when_quotes_missing() {
        assert_eq!(single_quoted_value("GIT_BRANCH=main", "GIT_BRANCH="), None);
    }

    #[test]
    fn single_quoted_value_handles_empty_value() {
        assert_eq!(
            single_quoted_value("GIT_PR_STATUS=''", "GIT_PR_STATUS="),
            Some("")
        );
    }

    #[test]
    fn extract_path_after_fields_returns_rest_after_n_whitespace() {
        // After 2 whitespace splits, path starts at "foo bar".
        assert_eq!(
            extract_path_after_fields("a b c foo bar", 3),
            Some("foo bar".to_string())
        );
    }

    #[test]
    fn extract_path_after_fields_handles_path_with_spaces() {
        // Porcelain v2 "1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>" → 8
        // whitespace skips reach the path. Path keeps its internal spaces.
        assert_eq!(
            extract_path_after_fields(
                "1 .M N... 100644 100644 100644 hashH hashI path with spaces",
                8
            ),
            Some("path with spaces".to_string())
        );
    }

    #[test]
    fn extract_path_after_fields_returns_none_when_too_few_fields() {
        assert_eq!(extract_path_after_fields("a b", 5), None);
    }

    #[test]
    fn tally_increments_staged_on_index_change() {
        let mut d = GitData::default();
        tally(&mut d, "M.");
        assert_eq!(d.staged_count, 1);
        assert_eq!(d.unstaged_count, 0);
        assert_eq!(d.conflict_count, 0);
    }

    #[test]
    fn tally_increments_unstaged_on_worktree_change() {
        let mut d = GitData::default();
        tally(&mut d, ".M");
        assert_eq!(d.unstaged_count, 1);
        assert_eq!(d.staged_count, 0);
    }

    #[test]
    fn tally_increments_both_on_staged_and_unstaged() {
        let mut d = GitData::default();
        tally(&mut d, "MM");
        assert_eq!(d.staged_count, 1);
        assert_eq!(d.unstaged_count, 1);
    }

    #[test]
    fn tally_detects_conflict_patterns() {
        for xy in ["UU", "AA", "DD", "AU", "UA", "DU", "UD"] {
            let mut d = GitData::default();
            tally(&mut d, xy);
            assert_eq!(d.conflict_count, 1, "expected conflict for {xy}");
            // Conflicts short-circuit; staged/unstaged stay zero.
            assert_eq!(d.staged_count, 0);
            assert_eq!(d.unstaged_count, 0);
        }
    }

    // Env-mutating tests share a process-wide mutex so they don't race against
    // each other when `cargo test` runs them in parallel. We can't simply
    // serialize via `--test-threads=1` because the user wants the suite fast.
    use std::sync::Mutex;
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn with_xdg_cache<F: FnOnce(&std::path::Path) -> R, R>(f: F) -> R {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let prior = std::env::var("XDG_CACHE_HOME").ok();
        let tmp = tempfile::TempDir::new().unwrap();
        std::env::set_var("XDG_CACHE_HOME", tmp.path());
        let r = f(tmp.path());
        if let Some(v) = prior {
            std::env::set_var("XDG_CACHE_HOME", v);
        } else {
            std::env::remove_var("XDG_CACHE_HOME");
        }
        r
    }

    #[test]
    fn cache_path_is_deterministic_for_same_input() {
        with_xdg_cache(|_| {
            let p1 = cache_path("/Users/jarvis/dotFiles").unwrap();
            let p2 = cache_path("/Users/jarvis/dotFiles").unwrap();
            assert_eq!(p1, p2);
            let name = p1.file_name().unwrap().to_str().unwrap();
            assert!(name.ends_with(".sh"));
            assert_eq!(name.len(), 15); // 12 hex chars + ".sh"
        });
    }

    #[test]
    fn cache_path_differs_for_different_repos() {
        with_xdg_cache(|_| {
            let p1 = cache_path("/path/one").unwrap();
            let p2 = cache_path("/path/two").unwrap();
            assert_ne!(p1, p2);
        });
    }

    #[test]
    fn cache_path_uses_xdg_cache_home_when_set() {
        with_xdg_cache(|root| {
            let p = cache_path("/x").unwrap();
            assert!(p.starts_with(root));
            assert!(p.parent().unwrap().ends_with("git-data"));
        });
    }

    #[test]
    fn write_cache_round_trip_persists_fields_with_mode_600() {
        with_xdg_cache(|_| {
            let mut d = GitData::default();
            d.is_repo = true;
            d.branch = "main".to_string();
            d.repo_name = "dotFiles".to_string();
            d.staged_count = 3;
            d.pr_status = "pass".to_string();
            d.pr_url = "https://github.com/x/y/pull/1".to_string();
            d.pr_number = 1;

            let path = cache_path("/test/repo").unwrap();
            write_cache(&path, &d).unwrap();

            let meta = std::fs::metadata(&path).unwrap();
            let mode = meta.permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);

            let content = std::fs::read_to_string(&path).unwrap();
            assert!(content.contains("GIT_IS_REPO='1'"));
            assert!(content.contains("GIT_BRANCH='main'"));
            assert!(content.contains("GIT_REPO_NAME='dotFiles'"));
            assert!(content.contains("GIT_STAGED_COUNT='3'"));
            assert!(content.contains("GIT_PR_STATUS='pass'"));

            // read_existing_pr_data should round-trip the PR fields.
            let pr = read_existing_pr_data(&path).unwrap();
            assert_eq!(pr.0, "pass");
            assert_eq!(pr.1, "https://github.com/x/y/pull/1");
            assert_eq!(pr.2, 1);
        });
    }

    #[test]
    fn read_existing_pr_data_returns_none_on_missing_file() {
        with_xdg_cache(|_| {
            let path = cache_path("/no/such/repo").unwrap();
            assert!(read_existing_pr_data(&path).is_none());
        });
    }
}
