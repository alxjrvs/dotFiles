// prune subcommand — backup-file cleanup.
//
// Finds `.bak` files left by `dotctl sync` link conflicts and the
// `.bak-<ISO>` files written by interactive tools (harness-tuneup, etc),
// lists them, and deletes after confirmation. Also called at the end of
// `dotctl sync` so the manager owns the lifecycle of the backups it
// produces.

use anyhow::Result;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

const GREEN: &str = "\x1b[0;32m";
const YELLOW: &str = "\x1b[0;33m";
const DIM: &str = "\x1b[2m";
const NC: &str = "\x1b[0m";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PromptMode {
    /// Show the list, prompt `[Y/n]`, default yes. Falls through to auto-yes
    /// when stdin isn't a TTY (matches the user's "assuming yes" directive).
    AskDefaultYes,
    /// Delete without prompting (used by non-interactive sync modes and `-y`).
    AutoYes,
    /// List only, never delete (`-n` / `--dry-run`).
    DryRun,
}

pub fn run(mode: PromptMode) -> Result<()> {
    let (home, dotfiles) = resolve_roots();
    prune_backups(&home, &dotfiles, mode)?;
    prune_stale_worktrees(&home, mode)?;
    Ok(())
}

fn prune_backups(home: &Path, dotfiles: &Path, mode: PromptMode) -> Result<()> {
    section();

    let backups = find_backups(home, dotfiles);
    if backups.is_empty() {
        println!("{GREEN}  ✓ No backups found{NC}");
        return Ok(());
    }

    println!("{YELLOW}  Found {} backup file(s):{NC}", backups.len());
    for b in &backups {
        println!("{DIM}    - {}{NC}", display_for(home, b));
    }

    let do_delete = match mode {
        PromptMode::AutoYes => true,
        PromptMode::DryRun => false,
        PromptMode::AskDefaultYes => prompt_default_yes(),
    };

    if !do_delete {
        println!("{DIM}  - Skipped (no files removed){NC}");
        return Ok(());
    }

    let mut deleted = 0usize;
    let mut failed = 0usize;
    for b in &backups {
        match fs::remove_file(b) {
            Ok(_) => deleted += 1,
            Err(e) => {
                eprintln!("{YELLOW}  → failed to delete {}: {e}{NC}", b.display());
                failed += 1;
            }
        }
    }
    if failed == 0 {
        println!("{GREEN}  ✓ Deleted {deleted} backup file(s){NC}");
    } else {
        println!("{YELLOW}  → Deleted {deleted}, {failed} failed{NC}");
    }
    Ok(())
}

// ─────────────────────────────────────────────── stale worktrees

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StaleReason {
    /// Parent repo's `.git` is gone — orphaned worktree.
    ParentGone,
    /// Parent repo exists but doesn't list this worktree (WorktreeRemove
    /// hook didn't fire, or parent's bookkeeping was force-cleaned).
    NotInParentList,
}

#[derive(Debug, Clone)]
pub struct StaleWorktree {
    pub path: PathBuf,
    pub parent_repo: Option<PathBuf>,
    pub reason: StaleReason,
    pub dirty: bool,
}

fn prune_stale_worktrees(home: &Path, mode: PromptMode) -> Result<()> {
    println!();
    println!("==> Stale worktree cleanup");

    let stale = find_stale_worktrees(home);
    if stale.is_empty() {
        println!("{GREEN}  ✓ No stale worktrees{NC}");
        return Ok(());
    }

    let removable: Vec<&StaleWorktree> = stale.iter().filter(|s| !s.dirty).collect();
    let dirty: Vec<&StaleWorktree> = stale.iter().filter(|s| s.dirty).collect();

    if !removable.is_empty() {
        println!(
            "{YELLOW}  Found {} stale worktree(s) safe to remove:{NC}",
            removable.len()
        );
        for s in &removable {
            let reason = match s.reason {
                StaleReason::ParentGone => "parent gone",
                StaleReason::NotInParentList => "not in parent list",
            };
            println!(
                "{DIM}    - {}  [{}]{NC}",
                display_for(home, &s.path),
                reason
            );
        }
    }

    if !dirty.is_empty() {
        println!(
            "{YELLOW}  Found {} stale worktree(s) with UNCOMMITTED changes (skipping):{NC}",
            dirty.len()
        );
        for s in &dirty {
            println!(
                "{DIM}    - {}  [DIRTY — inspect manually]{NC}",
                display_for(home, &s.path)
            );
        }
    }

    if removable.is_empty() {
        return Ok(());
    }

    let do_delete = match mode {
        PromptMode::AutoYes => true,
        PromptMode::DryRun => false,
        PromptMode::AskDefaultYes => prompt_worktrees_default_yes(),
    };
    if !do_delete {
        println!("{DIM}  - Skipped (no worktrees removed){NC}");
        return Ok(());
    }

    let mut removed = 0usize;
    let mut failed = 0usize;
    for s in &removable {
        match remove_stale_worktree(s) {
            Ok(()) => removed += 1,
            Err(e) => {
                eprintln!(
                    "{YELLOW}  → failed to remove {}: {e}{NC}",
                    s.path.display()
                );
                failed += 1;
            }
        }
    }
    if failed == 0 {
        println!("{GREEN}  ✓ Removed {removed} stale worktree(s){NC}");
    } else {
        println!("{YELLOW}  → Removed {removed}, {failed} failed{NC}");
    }
    Ok(())
}

pub fn find_stale_worktrees(home: &Path) -> Vec<StaleWorktree> {
    let root = home.join(".local/share/cc-worktrees");
    if !root.is_dir() {
        return vec![];
    }
    let mut out = Vec::new();
    let Ok(repos) = fs::read_dir(&root) else { return out };
    for repo_entry in repos.flatten() {
        let repo_dir = repo_entry.path();
        if !repo_dir.is_dir() {
            continue;
        }
        let Ok(wts) = fs::read_dir(&repo_dir) else { continue };
        for wt_entry in wts.flatten() {
            let wt_path = wt_entry.path();
            if !wt_path.is_dir() {
                continue;
            }
            if let Some(stale) = classify_worktree(&wt_path) {
                out.push(stale);
            }
        }
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

// Returns Some(StaleWorktree) if the dir at wt_path is a worktree that's
// detached from any active parent, None if it's still actively tracked.
fn classify_worktree(wt_path: &Path) -> Option<StaleWorktree> {
    // Resolve parent's .git common-dir.
    let common_out = Command::new("git")
        .args(["-C", wt_path.to_str()?, "rev-parse", "--git-common-dir"])
        .output()
        .ok()?;
    let dirty = is_worktree_dirty(wt_path);
    if !common_out.status.success() {
        return Some(StaleWorktree {
            path: wt_path.to_path_buf(),
            parent_repo: None,
            reason: StaleReason::ParentGone,
            dirty,
        });
    }
    let common_dir =
        PathBuf::from(String::from_utf8_lossy(&common_out.stdout).trim());
    // common_dir is <parent-repo>/.git ; parent dir is one up.
    let Some(parent_repo) = common_dir.parent().map(|p| p.to_path_buf()) else {
        return Some(StaleWorktree {
            path: wt_path.to_path_buf(),
            parent_repo: None,
            reason: StaleReason::ParentGone,
            dirty,
        });
    };
    if !parent_repo.is_dir() {
        return Some(StaleWorktree {
            path: wt_path.to_path_buf(),
            parent_repo: None,
            reason: StaleReason::ParentGone,
            dirty,
        });
    }
    // Ask parent whether it knows about this worktree.
    let list_out = Command::new("git")
        .args([
            "-C",
            parent_repo.to_str()?,
            "worktree",
            "list",
            "--porcelain",
        ])
        .output()
        .ok()?;
    let wt_real = fs::canonicalize(wt_path).ok()?;
    let mut found = false;
    if list_out.status.success() {
        let listed = String::from_utf8_lossy(&list_out.stdout);
        for line in listed.lines() {
            if let Some(p) = line.strip_prefix("worktree ") {
                if let Ok(p_real) = fs::canonicalize(p) {
                    if p_real == wt_real {
                        found = true;
                        break;
                    }
                }
            }
        }
    }
    if found {
        return None;
    }
    Some(StaleWorktree {
        path: wt_path.to_path_buf(),
        parent_repo: Some(parent_repo),
        reason: StaleReason::NotInParentList,
        dirty,
    })
}

fn is_worktree_dirty(wt_path: &Path) -> bool {
    let Some(s) = wt_path.to_str() else { return false };
    let out = match Command::new("git")
        .args(["-C", s, "status", "--porcelain"])
        .output()
    {
        Ok(o) if o.status.success() => o,
        // If git status fails, fall back to assuming clean — the parent
        // path checks have already classified this as stale.
        _ => return false,
    };
    !out.stdout.is_empty()
}

fn remove_stale_worktree(s: &StaleWorktree) -> Result<()> {
    if let Some(parent) = &s.parent_repo {
        // Best-effort git removal first (cleans parent bookkeeping).
        let _ = Command::new("git")
            .args([
                "-C",
                parent.to_str().ok_or_else(|| anyhow::anyhow!("non-utf8 parent path"))?,
                "worktree",
                "remove",
                "--force",
                s.path.to_str().ok_or_else(|| anyhow::anyhow!("non-utf8 wt path"))?,
            ])
            .output();
        let _ = Command::new("git")
            .args([
                "-C",
                parent.to_str().unwrap(),
                "worktree",
                "prune",
            ])
            .output();
    }
    // If the dir is still present (git refused or no parent), nuke it.
    if s.path.exists() {
        fs::remove_dir_all(&s.path)?;
    }
    Ok(())
}

fn prompt_worktrees_default_yes() -> bool {
    if !io::stdin().is_terminal() {
        println!("{DIM}  - Non-interactive; removing (default yes){NC}");
        return true;
    }
    print!("       Remove these worktrees? [Y/n]: ");
    let _ = io::stdout().flush();
    let mut s = String::new();
    if io::stdin().read_line(&mut s).is_err() {
        return false;
    }
    let answer = s.trim().to_lowercase();
    answer.is_empty() || answer == "y" || answer == "yes"
}

fn section() {
    println!();
    println!("==> Backup cleanup");
}

fn resolve_roots() -> (PathBuf, PathBuf) {
    let home = std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    let dotfiles = std::env::var("DOTFILES_DIR")
        .map(PathBuf::from)
        .ok()
        .filter(|p| p.is_dir())
        .unwrap_or_else(|| home.join("dotFiles"));
    (home, dotfiles)
}

fn display_for(home: &Path, p: &Path) -> String {
    p.strip_prefix(home)
        .map(|rel| format!("~/{}", rel.display()))
        .unwrap_or_else(|_| p.display().to_string())
}

pub fn find_backups(home: &Path, _dotfiles: &Path) -> Vec<PathBuf> {
    // Scope: only paths dotctl owns or routinely writes. Do NOT scan the
    // dotfiles repo or arbitrary HOME subtrees — risk of nuking unrelated
    // user backups.
    let scan_roots: &[(&Path, u32)] = &[
        (home, 1),                                // ~/<file>.bak only (no recursion)
        (&home.join(".config"), 4),               // ~/.config/**/*.bak
        (&home.join(".claude"), 4),               // ~/.claude/**/*.bak{,-ISO}
        (&home.join(".ssh"), 1),                  // ~/.ssh/*.bak
    ];

    let mut out: Vec<PathBuf> = Vec::new();
    for (root, depth) in scan_roots {
        if !root.is_dir() {
            continue;
        }
        walk(root, *depth, &mut |p| {
            if is_backup_file(p) {
                out.push(p.to_path_buf());
            }
        });
    }
    out.sort();
    out.dedup();
    out
}

fn walk<F: FnMut(&Path)>(dir: &Path, depth: u32, cb: &mut F) {
    if depth == 0 {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let p = entry.path();
        // Skip noisy/large/irrelevant subtrees.
        if let Some(name) = p.file_name().and_then(|s| s.to_str()) {
            if matches!(
                name,
                ".git" | "node_modules" | "target" | "share" | "Caches" | "installs"
            ) {
                continue;
            }
        }
        let meta = match fs::symlink_metadata(&p) {
            Ok(m) => m,
            Err(_) => continue,
        };
        if meta.file_type().is_symlink() {
            // Don't follow symlinks — could loop into mise/cargo install dirs.
            continue;
        }
        if meta.is_dir() {
            walk(&p, depth - 1, cb);
        } else if meta.is_file() {
            cb(&p);
        }
    }
}

fn is_backup_file(p: &Path) -> bool {
    let Some(name) = p.file_name().and_then(|s| s.to_str()) else {
        return false;
    };
    // `<x>.bak` (dotctl sync link-conflict backup; matches the
    // `<dst>.bak` pattern in sync.rs::link()).
    if name.ends_with(".bak") {
        return true;
    }
    // `<x>.bak-<ISO>` (harness-tuneup writes `.bak-<ISO>` files;
    // `.gitignore` matches the same pattern).
    if let Some(idx) = name.find(".bak-") {
        let suffix = &name[idx + ".bak-".len()..];
        if !suffix.is_empty() {
            return true;
        }
    }
    // `<x>.bak.<anything>` (defensive — some tools chain a timestamp after).
    if name.contains(".bak.") {
        return true;
    }
    false
}

fn prompt_default_yes() -> bool {
    if !io::stdin().is_terminal() {
        // Non-interactive: honor the "default yes" directive without
        // blocking — matches the user's "assuming yes" semantics.
        println!("{DIM}  - Non-interactive; deleting (default yes){NC}");
        return true;
    }
    print!("       Delete these backups? [Y/n]: ");
    let _ = io::stdout().flush();
    let mut s = String::new();
    if io::stdin().read_line(&mut s).is_err() {
        return false;
    }
    let answer = s.trim().to_lowercase();
    answer.is_empty() || answer == "y" || answer == "yes"
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn is_backup_file_matches_bare_bak() {
        assert!(is_backup_file(Path::new("/tmp/.gitconfig.bak")));
        assert!(is_backup_file(Path::new("/tmp/karabiner.json.pre-dotctl.bak")));
    }

    #[test]
    fn is_backup_file_matches_iso_suffix() {
        assert!(is_backup_file(Path::new(
            "/tmp/settings.json.bak-2026-05-18T07:00:00Z"
        )));
    }

    #[test]
    fn is_backup_file_matches_dotted_suffix() {
        assert!(is_backup_file(Path::new("/tmp/cfg.bak.20260518")));
    }

    #[test]
    fn is_backup_file_rejects_non_backups() {
        assert!(!is_backup_file(Path::new("/tmp/.gitconfig")));
        assert!(!is_backup_file(Path::new("/tmp/backup.txt")));
        assert!(!is_backup_file(Path::new("/tmp/.bakery")));
    }

    #[test]
    fn is_backup_file_rejects_empty_iso_suffix() {
        // `.bak-` with nothing after isn't a tuneup file shape.
        assert!(!is_backup_file(Path::new("/tmp/cfg.bak-")));
    }

    #[test]
    fn find_backups_picks_up_files_in_scoped_roots() {
        let tmp = TempDir::new().unwrap();
        let home = tmp.path();
        std::fs::write(home.join(".gitconfig.bak"), "x").unwrap();
        std::fs::create_dir_all(home.join(".config/atuin")).unwrap();
        std::fs::write(home.join(".config/atuin/config.toml.bak"), "x").unwrap();
        std::fs::create_dir_all(home.join(".claude")).unwrap();
        std::fs::write(
            home.join(".claude/settings.json.bak-2026-05-18T07:00:00Z"),
            "x",
        )
        .unwrap();
        // Non-backup decoy
        std::fs::write(home.join(".zshrc"), "x").unwrap();
        let backups = find_backups(home, home);
        assert_eq!(backups.len(), 3, "found: {:?}", backups);
    }

    #[test]
    fn find_backups_ignores_unscoped_subtrees() {
        let tmp = TempDir::new().unwrap();
        let home = tmp.path();
        // ~/random/x.bak should NOT be picked up (not in scoped roots).
        std::fs::create_dir_all(home.join("random")).unwrap();
        std::fs::write(home.join("random/x.bak"), "x").unwrap();
        let backups = find_backups(home, home);
        assert!(backups.is_empty(), "found unexpected: {:?}", backups);
    }
}
