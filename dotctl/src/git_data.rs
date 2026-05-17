// git-data subcommand — Rust port of scripts/git-data.sh.
//
// Gathers git state in a single pass and writes a shell-sourceable cache
// file at $XDG_CACHE_HOME/git-data/<repo-hash>.sh (mode 600, dir 700).
// Cache key is the repo toplevel (or cwd if outside a repo).
//
// Output format matches scripts/git-data.sh exactly so existing zsh
// consumers (`source $cache_file`) work unchanged.
//
// Variables emitted:
//   GIT_IS_REPO, GIT_IS_WORKTREE, GIT_WORKTREE_NAME, GIT_DIR,
//   GIT_TOPLEVEL, GIT_BRANCH, GIT_REMOTE_URL, GIT_REPO_NAME,
//   GIT_REPO_HTTPS, GIT_PORCELAIN, GIT_CONFLICT_COUNT, GIT_STAGED_COUNT,
//   GIT_UNSTAGED_COUNT, GIT_UNTRACKED_COUNT, GIT_STASH_COUNT,
//   GIT_AHEAD, GIT_BEHIND, GIT_CACHE_TIME

use anyhow::Result;
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
}

pub fn run() -> Result<()> {
    let data = gather();
    let cache_file = cache_path(&data.toplevel)?;
    write_cache(&cache_file, &data)?;
    Ok(())
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
         GIT_BEHIND='{behind}'\n",
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

// Cheap RFC-1123-ish timestamp without bringing in chrono. The bash script
// uses `date` which produces system-local "Sat May 17 14:30:12 PDT 2026"
// style output — but the cache header is informational only and consumers
// don't parse it. Just emit something readable.
fn format_human_time(epoch_secs: u64) -> String {
    // Use the system `date` command to match the bash output style exactly.
    // Cheap one-time fork; happens once per cache write (low frequency).
    Command::new("date")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| epoch_secs.to_string())
}
