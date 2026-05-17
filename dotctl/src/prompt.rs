// prompt-render subcommand — Rust port of zsh/50-prompt.zsh.
//
// Reads $XDG_CACHE_HOME/git-data/<hash>.sh directly (no env-sourcing
// dance required). Emits a powerline prompt with %{...%} escapes for
// zsh PROMPT-syntax (so zsh's length calculator gets it right).
//
// Layout (Nord palette, Snow Storm bg + Aurora pip colors):
//
//   ┌───────────────┐ ┌────┐ ┌─────────┐ ┌──┐ ┌──┐
//   │ repo OR cwd │ │GH│ │ branch │ │WT│ │ pips │
//   └───────────────┘ └────┘ └─────────┘ └──┘ └──┘
//
// The repo/cwd cell uses Snow Storm 1 bg. The GH icon cell uses the PR
// status color (pass=green / pending=amber / fail=red / default=Nord 1).
// Worktree cell only renders when STATUSLINE_WORKTREE or GIT_IS_WORKTREE.

use anyhow::Result;
use std::collections::HashMap;
use std::env;

use crate::git_data;

// ── ANSI escape primitives (use zsh PROMPT-syntax %{...%}) ───────────────
//
// All escapes are wrapped in %{ ... %} so zsh doesn't count their bytes
// against the prompt width. Failing to wrap causes catastrophic prompt
// reflow when terminal is resized.
const RST: &str = "%{\x1b[0m%}";
const UL: &str = "%{\x1b[4m%}";
const NUL: &str = "%{\x1b[24m%}";

// Powerline glyphs (Nerd Font PUA range).
const ARROW_R: &str = "\u{e0b0}"; // right triangle separator
const WEDGE_O: &str = "\u{e0ba}"; // opening wedge (concave)
const GH_ICON: &str = "\u{f09b}"; // GitHub mark

// ── Nord-derived RGB triples (canonical: scripts/theme.sh) ───────────────
type Rgb = (u8, u8, u8);
const TERM_BG: Rgb = (46, 52, 64); // #2E3440 — Nord 0 terminal bg
const SS1: Rgb = (216, 222, 233); // #D8DEE9 — Snow Storm 1 (identity bg, branch pill bg)
const FG_LIGHT: Rgb = (236, 239, 244); // #ECEFF4 — Nord 6
const FG_DARK: Rgb = (46, 52, 64); // = TERM_BG — dark text on SS1
const NORD_1: Rgb = (59, 66, 82); // #3B4252 — fallback PR cell bg
const NOVA_WORKTREE: Rgb = (94, 129, 172); // #5E81AC — Nord 10 Frost
const NOVA_BG: Rgb = (46, 52, 64); // same as TERM_BG

// PR status palette (color of GH icon cell)
const PR_PASS: Rgb = (163, 190, 140); // Nord 14 — Aurora green
const PR_PENDING: Rgb = (235, 203, 139); // Nord 13 — Aurora amber
const PR_FAIL: Rgb = (191, 97, 106); // Nord 11 — Aurora red

// Git status pip colors
const GIT_STASH: Rgb = (180, 142, 173); // Nord 15
const GIT_CONFLICT: Rgb = (191, 97, 106); // Nord 11
const GIT_STAGED: Rgb = (163, 190, 140); // Nord 14
const GIT_UNSTAGED: Rgb = (235, 203, 139); // Nord 13
const GIT_UNTRACKED: Rgb = (129, 161, 193); // Nord 9
const GIT_AHEAD: Rgb = (208, 135, 112); // Nord 12
const GIT_BEHIND: Rgb = (94, 129, 172); // Nord 10
const GIT_CLEAN: Rgb = (163, 190, 140); // Nord 14

fn fg(rgb: Rgb) -> String {
    format!("%{{\x1b[38;2;{};{};{}m%}}", rgb.0, rgb.1, rgb.2)
}
fn bg(rgb: Rgb) -> String {
    format!("%{{\x1b[48;2;{};{};{}m%}}", rgb.0, rgb.1, rgb.2)
}
fn osc8_open(url: &str) -> String {
    format!("%{{\x1b]8;;{url}\x07%}}")
}
fn osc8_close() -> &'static str {
    "%{\x1b]8;;\x07%}"
}

fn get(cache: &HashMap<String, String>, key: &str) -> String {
    cache.get(key).cloned().unwrap_or_default()
}

fn get_u32(cache: &HashMap<String, String>, key: &str) -> u32 {
    cache.get(key).and_then(|s| s.parse().ok()).unwrap_or(0)
}

pub fn run() -> Result<()> {
    let cache = git_data::load_cache();
    let mut out = String::new();
    render_repo_dir(&mut out, &cache);
    render_git_seg(&mut out, &cache);
    println!("{out} ");
    Ok(())
}

// ── Identity cell: repo (linked, underlined) OR last 2 path components ──
fn render_repo_dir(o: &mut String, cache: &HashMap<String, String>) {
    let repo_name = get(cache, "GIT_REPO_NAME");
    let repo_https = get(cache, "GIT_REPO_HTTPS");
    let pr_status = get(cache, "GIT_PR_STATUS");
    let pr_url = get(cache, "GIT_PR_URL");
    let is_repo = get(cache, "GIT_IS_REPO") == "1";

    // PR cell colors default to Nord 1 / Snow Storm 1.
    let (pr_bg, pr_fg) = match pr_status.as_str() {
        "pass" => (PR_PASS, FG_DARK),
        "pending" => (PR_PENDING, FG_DARK),
        "fail" => (PR_FAIL, FG_LIGHT),
        _ => (NORD_1, FG_LIGHT),
    };

    // Opening wedge from terminal bg into SS1 cell.
    o.push_str(&bg(TERM_BG));
    o.push_str(&fg(SS1));
    o.push_str(WEDGE_O);

    // SS1 cell with dark text
    o.push_str(&bg(SS1));
    o.push_str(&fg(FG_DARK));

    if !repo_name.is_empty() {
        // Repo name: underlined, OSC8-linked to the HTTPS URL.
        o.push(' ');
        o.push_str(UL);
        o.push_str(&osc8_open(&repo_https));
        o.push_str(&repo_name);
        o.push_str(osc8_close());
        o.push_str(NUL);
        o.push(' ');

        // SS1 → PR cell arrow.
        o.push_str(&bg(pr_bg));
        o.push_str(&fg(SS1));
        o.push_str(ARROW_R);

        // GH icon, optionally OSC8-linked to PR URL.
        o.push_str(&fg(pr_fg));
        o.push(' ');
        if !pr_url.is_empty() {
            o.push_str(&osc8_open(&pr_url));
            o.push_str(GH_ICON);
            o.push_str(osc8_close());
        } else {
            o.push_str(GH_ICON);
        }
        o.push(' ');
    } else {
        // Bare CWD fallback: last 2 path components, no link.
        let display = cwd_display();
        o.push(' ');
        o.push_str(&display);
        o.push(' ');
        if !is_repo {
            // Close cell with the SS1 → TERM_BG arrow.
            o.push_str(RST);
            o.push_str(&fg(SS1));
            o.push_str(ARROW_R);
            o.push_str(RST);
        }
    }
}

// ── Git segment: branch pill + optional worktree cell + status pips ──
fn render_git_seg(o: &mut String, cache: &HashMap<String, String>) {
    if get(cache, "GIT_IS_REPO") != "1" {
        return;
    }
    let branch = get(cache, "GIT_BRANCH");
    let repo_name = get(cache, "GIT_REPO_NAME");
    let pr_status = get(cache, "GIT_PR_STATUS");

    // Arrow from previous cell into branch pill (SS1 bg).
    let from_color = if !repo_name.is_empty() {
        match pr_status.as_str() {
            "pass" => PR_PASS,
            "pending" => PR_PENDING,
            "fail" => PR_FAIL,
            _ => NORD_1,
        }
    } else {
        // Seamless from identity (both SS1) — invisible arrow.
        SS1
    };
    o.push_str(&bg(SS1));
    o.push_str(&fg(from_color));
    o.push_str(ARROW_R);
    o.push_str(&fg(FG_DARK));
    o.push(' ');
    o.push_str(&branch);
    o.push(' ');
    let mut prev: Rgb = SS1;

    // Worktree cell: STATUSLINE_WORKTREE (env, set by Claude statusline)
    // overrides; else auto from GIT_IS_WORKTREE cache field.
    let wt_label = {
        let env_wt = env::var("STATUSLINE_WORKTREE").unwrap_or_default();
        if !env_wt.is_empty() {
            env_wt
        } else if get(cache, "GIT_IS_WORKTREE") == "1" {
            get(cache, "GIT_WORKTREE_NAME")
        } else {
            String::new()
        }
    };
    if !wt_label.is_empty() {
        o.push_str(&bg(NOVA_WORKTREE));
        o.push_str(&fg(prev));
        o.push_str(ARROW_R);
        o.push_str(&fg(NOVA_BG));
        o.push(' ');
        o.push_str(&wt_label);
        o.push(' ');
        prev = NOVA_WORKTREE;
    }

    let push_pip = |o: &mut String, prev: &mut Rgb, color: Rgb, label: &str| {
        o.push_str(&bg(color));
        o.push_str(&fg(*prev));
        o.push_str(ARROW_R);
        o.push_str(&fg(NOVA_BG));
        o.push(' ');
        o.push_str(label);
        o.push(' ');
        *prev = color;
    };

    let stash = get_u32(cache, "GIT_STASH_COUNT");
    let conflict = get_u32(cache, "GIT_CONFLICT_COUNT");
    let untracked = get_u32(cache, "GIT_UNTRACKED_COUNT");
    let unstaged = get_u32(cache, "GIT_UNSTAGED_COUNT");
    let staged = get_u32(cache, "GIT_STAGED_COUNT");
    let ahead = get_u32(cache, "GIT_AHEAD");
    let behind = get_u32(cache, "GIT_BEHIND");

    let mut any = false;
    if stash > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_STASH, &format!("${stash}"));
    }
    if conflict > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_CONFLICT, &format!("!{conflict}"));
    }
    if untracked > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_UNTRACKED, &format!("?{untracked}"));
    }
    if unstaged > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_UNSTAGED, &format!("~{unstaged}"));
    }
    if staged > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_STAGED, &format!("+{staged}"));
    }
    if ahead > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_AHEAD, &format!("\u{2191}{ahead}"));
    }
    if behind > 0 {
        any = true;
        push_pip(o, &mut prev, GIT_BEHIND, &format!("\u{2193}{behind}"));
    }
    if !any {
        push_pip(o, &mut prev, GIT_CLEAN, "\u{2713}");
    }

    // Closing arrow.
    o.push_str(RST);
    o.push_str(&fg(prev));
    o.push_str(ARROW_R);
    o.push_str(RST);
}

// Last 2 path components of PWD with ~ for $HOME.
fn cwd_display() -> String {
    let pwd = env::var("PWD").unwrap_or_else(|_| ".".into());
    let home = env::var("HOME").unwrap_or_default();
    let shown: String = if !home.is_empty() && pwd.starts_with(&home) {
        let rel = &pwd[home.len()..];
        if rel.is_empty() {
            "~".to_string()
        } else {
            format!("~{rel}")
        }
    } else {
        pwd.clone()
    };
    let parts: Vec<&str> = shown.split('/').filter(|s| !s.is_empty()).collect();
    if shown.starts_with('~') {
        // "~/a/b/c" → "b/c"; "~/foo" → "~/foo"; "~" → "~"
        if parts.len() >= 3 {
            format!("{}/{}", parts[parts.len() - 2], parts[parts.len() - 1])
        } else {
            shown
        }
    } else if parts.len() >= 2 {
        format!("{}/{}", parts[parts.len() - 2], parts[parts.len() - 1])
    } else {
        shown
    }
}
