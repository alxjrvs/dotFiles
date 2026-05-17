// statusline subcommand — Rust port of dot-claude/statusline-command.sh.
//
// Reads Claude statusline JSON from stdin; refreshes git cache; emits a
// 3–5 line plain-ASCII statusline with colored git values + progress
// bars for context window + Pro/Max rate-limit windows.
//
// Layout:
//   Line 1: repo/dir [branch] [wt:name] [counters]
//   Line 2: [M: model] [A: advisor] [E: effort]   (optional)
//   Line 3: Ctx [bar] N%
//   Line 4: 5h  [bar] N% [time left] [delta]
//   Line 5: 7d  [bar] N% [time left] [delta]

use anyhow::Result;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Read};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::git_data;

// ── Style primitives (no zsh wrapping — statusline output isn't a prompt) ──
const UNDIM: &str = "\x1b[22m";
const BOLD: &str = "\x1b[1m";
const RST: &str = "\x1b[0m";
const MUTED: &str = "\x1b[90m";
const RED: &str = "\x1b[31m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const BLUE: &str = "\x1b[34m";
const MAGENTA: &str = "\x1b[35m";
const CYAN: &str = "\x1b[36m";
const NEAR_WHITE: &str = "\x1b[38;2;235;235;235m";
const MARKER: &str = "\x1b[38;2;96;200;255m";
const PROJ: &str = "\x1b[38;2;255;210;80m";

const PIP_COUNT: usize = 30;
const PIP_FILL: char = '\u{25B0}'; // ▰
const PIP_EMPTY: char = '\u{25B1}'; // ▱

pub fn run() -> Result<()> {
    let mut input = String::new();
    let _ = io::stdin().read_to_string(&mut input);
    let payload: Value = serde_json::from_str(&input).unwrap_or(Value::Null);

    // Refresh + read git cache so GIT_* values are current.
    let _ = git_data::run();
    let git = load_git_cache();

    let used_pct = str_at(&payload, &["context_window", "used_percentage"]);
    let worktree_name_input = str_at(&payload, &["worktree", "name"]);
    let project_dir = str_at(&payload, &["workspace", "project_dir"]);
    let cwd_input = str_at(&payload, &["workspace", "current_dir"]);
    let model_name = str_at(&payload, &["model", "display_name"]);
    let effort_level = str_at(&payload, &["effort", "level"]);
    let five_pct = str_at(&payload, &["rate_limits", "five_hour", "used_percentage"]);
    let five_resets_at = str_at(&payload, &["rate_limits", "five_hour", "resets_at"]);
    let seven_pct = str_at(&payload, &["rate_limits", "seven_day", "used_percentage"]);
    let seven_resets_at = str_at(&payload, &["rate_limits", "seven_day", "resets_at"]);

    // Advisor name comes from ~/.claude/settings.json (.advisorModel).
    let advisor_name = read_advisor_name();

    // CWD: prefer project_dir when in a worktree.
    let cwd = if !worktree_name_input.is_empty() && !project_dir.is_empty() {
        project_dir.clone()
    } else if !cwd_input.is_empty() {
        cwd_input.clone()
    } else {
        std::env::current_dir()
            .ok()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default()
    };
    let dir_display = last_two_components_with_home(&cwd);

    // ── Line 1 ────────────────────────────────────────────────────────
    let repo_url = git.get("GIT_REPO_HTTPS").cloned().unwrap_or_default();
    let repo_name = git.get("GIT_REPO_NAME").cloned().unwrap_or_default();
    let branch = git.get("GIT_BRANCH").cloned().unwrap_or_default();

    let id_part = if !repo_name.is_empty() {
        // OSC8: linked, bold, near-white.
        format!(
            "\x1b]8;;{repo_url}\x07{BOLD}{NEAR_WHITE}{repo_name}{RST}\x1b]8;;\x07"
        )
    } else {
        format!("{BOLD}{NEAR_WHITE}{dir_display}{RST}")
    };

    let mut line1 = id_part;
    let is_repo = git.get("GIT_IS_REPO").map(|s| s == "1").unwrap_or(false);
    if is_repo || !branch.is_empty() {
        let b = if branch.is_empty() { "-".to_string() } else { branch.clone() };
        line1.push_str(&format!(" {MUTED}[{RST}{BLUE}{b}{MUTED}]{RST}"));
    }

    let wt = if !worktree_name_input.is_empty() {
        worktree_name_input.clone()
    } else {
        git.get("GIT_WORKTREE_NAME").cloned().unwrap_or_default()
    };
    if !wt.is_empty() {
        line1.push_str(&format!(" {MUTED}[{RST}{MAGENTA}{wt}{MUTED}]{RST}"));
    }

    // Counters
    let mut counters: Vec<String> = Vec::new();
    fn pl<'a>(n: u32, sg: &'a str, pl: &'a str) -> &'a str {
        if n == 1 { sg } else { pl }
    }
    let n = |k: &str| git.get(k).and_then(|s| s.parse::<u32>().ok()).unwrap_or(0);
    if n("GIT_STASH_COUNT") > 0 {
        let c = n("GIT_STASH_COUNT");
        counters.push(format!("{MAGENTA}{c} {}{RST}", pl(c, "stash", "stashes")));
    }
    if n("GIT_CONFLICT_COUNT") > 0 {
        let c = n("GIT_CONFLICT_COUNT");
        counters.push(format!("{BOLD}{RED}{c} {}{RST}", pl(c, "conflict", "conflicts")));
    }
    if n("GIT_UNTRACKED_COUNT") > 0 {
        counters.push(format!("{CYAN}{} untracked{RST}", n("GIT_UNTRACKED_COUNT")));
    }
    if n("GIT_UNSTAGED_COUNT") > 0 {
        counters.push(format!("{YELLOW}{} modified{RST}", n("GIT_UNSTAGED_COUNT")));
    }
    if n("GIT_STAGED_COUNT") > 0 {
        counters.push(format!("{GREEN}{} staged{RST}", n("GIT_STAGED_COUNT")));
    }
    if n("GIT_AHEAD") > 0 {
        counters.push(format!("{GREEN}{} ahead{RST}", n("GIT_AHEAD")));
    }
    if n("GIT_BEHIND") > 0 {
        counters.push(format!("{RED}{} behind{RST}", n("GIT_BEHIND")));
    }
    if !counters.is_empty() {
        line1.push_str(&format!(
            " {MUTED}[{RST}{}{MUTED}]{RST}",
            counters.join(&format!("{MUTED}, {RST}"))
        ));
    }
    println!("{line1}");

    // ── Line 2 ────────────────────────────────────────────────────────
    let mut line2 = String::new();
    if !model_name.is_empty() {
        line2.push_str(&format!("{MUTED}[{RST}{CYAN}M: {model_name}{MUTED}]{RST}"));
    }
    if !advisor_name.is_empty() {
        if !line2.is_empty() {
            line2.push(' ');
        }
        line2.push_str(&format!("{MUTED}[{RST}{CYAN}A: {advisor_name}{MUTED}]{RST}"));
    }
    if !effort_level.is_empty() {
        if !line2.is_empty() {
            line2.push(' ');
        }
        line2.push_str(&format!("{MUTED}[{RST}{CYAN}E: {effort_level}{MUTED}]{RST}"));
    }
    if !line2.is_empty() {
        println!("{line2}");
    }

    // ── Line 3: Ctx bar ───────────────────────────────────────────────
    let used_int = parse_int_prefix(&used_pct);
    let ctx_bar = render_bar(used_int, None, None);
    println!(
        "{MUTED}{:<3}{RST} {ctx_bar} {MUTED}{:3}%{RST}",
        "Ctx", used_int
    );

    // ── Lines 4-5: rate-limit windows ─────────────────────────────────
    print_window(&five_pct, &five_resets_at, 300, "5h");
    print_window(&seven_pct, &seven_resets_at, 10_080, "7d");

    Ok(())
}

fn print_window(pct_str: &str, resets_at_str: &str, window_min: u64, label: &str) {
    if pct_str.is_empty() || resets_at_str.is_empty() {
        if label == "5h" {
            println!(
                "{MUTED}{:<3}{RST} {MUTED}[ rate_limits unavailable — make a request to populate ]{RST}",
                label
            );
        }
        return;
    }
    let pct = parse_int_prefix(pct_str);
    let resets_at: u64 = resets_at_str.parse().unwrap_or(0);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let remain_sec = resets_at.saturating_sub(now);
    let remain_min = (remain_sec / 60).min(window_min);
    let clock_pct = ((window_min - remain_min) * 100 / window_min) as i32;
    let proj_pct = if clock_pct > 5 {
        Some(pct as i32 * 100 / clock_pct)
    } else {
        None
    };
    let delta = pct as i32 - clock_pct;
    let delta_str = if delta > 0 {
        format!("{RED}+{delta}%{RST}")
    } else if delta < 0 {
        format!("{GREEN}{delta}%{RST}")
    } else {
        format!("{MUTED}0%{RST}")
    };

    let time_label = if remain_min >= 1440 {
        let d = remain_min / 1440;
        let h = (remain_min % 1440) / 60;
        format!("{d}d {h:02}h left")
    } else if remain_min >= 60 {
        let h = remain_min / 60;
        let m = remain_min % 60;
        format!("{h}h {m:02}m left")
    } else {
        format!("{remain_min}m left")
    };

    let bar = render_bar(pct, Some(clock_pct), proj_pct);
    println!(
        "{MUTED}{:<3}{RST} {bar} {MUTED}{:3}%{RST} [{MARKER}{time_label}{MUTED}] [{}{MUTED}]{RST}",
        label, pct, delta_str
    );
}

// Blackbody-style gradient sampled at 30 stops.
fn gradient_at(t: i32) -> (u8, u8, u8) {
    let (r, g, b) = if t <= 3500 {
        let u = t * 10_000 / 3500;
        (
            74 + (176 - 74) * u / 10_000,
            79 + (74 - 79) * u / 10_000,
            92 + (58 - 92) * u / 10_000,
        )
    } else if t <= 7000 {
        let u = (t - 3500) * 10_000 / 3500;
        (
            176 + (240 - 176) * u / 10_000,
            74 + (160 - 74) * u / 10_000,
            58 + (64 - 58) * u / 10_000,
        )
    } else if t <= 9000 {
        let u = (t - 7000) * 10_000 / 2000;
        (
            240 + (255 - 240) * u / 10_000,
            160 + (232 - 160) * u / 10_000,
            64 + (144 - 64) * u / 10_000,
        )
    } else {
        let u = (t - 9000) * 10_000 / 1000;
        (255i32, 232 + (255 - 232) * u / 10_000, 144 + (255 - 144) * u / 10_000)
    };
    (r as u8, g as u8, b as u8)
}

fn render_bar(pct: i32, marker_pct: Option<i32>, proj_pct: Option<i32>) -> String {
    let pct = pct.max(0);
    let mut filled = (pct as usize) * PIP_COUNT / 100;
    if filled > PIP_COUNT {
        filled = PIP_COUNT;
    }
    if pct > 0 && filled == 0 {
        filled = 1;
    }

    let (marker_idx, marker_expired): (Option<usize>, bool) = match marker_pct {
        Some(m) if m >= 100 => (Some(PIP_COUNT - 1), true),
        Some(m) => {
            let idx = (m.max(0) as usize) * PIP_COUNT / 100;
            (Some(idx.min(PIP_COUNT - 1)), false)
        }
        None => (None, false),
    };
    let proj_idx: Option<usize> = match proj_pct {
        Some(p) if (0..=100).contains(&p) => {
            let idx = (p as usize) * PIP_COUNT / 100;
            Some(idx.min(PIP_COUNT - 1))
        }
        _ => None,
    };

    // Pre-compute per-pip gradient color.
    let mut pip_colors: Vec<(u8, u8, u8)> = Vec::with_capacity(PIP_COUNT);
    for k in 0..PIP_COUNT {
        pip_colors.push(gradient_at((k as i32) * 10_000 / (PIP_COUNT as i32 - 1)));
    }

    let mut out = String::new();
    for i in 0..PIP_COUNT {
        let pip = if i < filled { PIP_FILL } else { PIP_EMPTY };
        if Some(i) == marker_idx {
            if marker_expired {
                out.push_str(&format!("{UNDIM}{RED}{pip}"));
            } else {
                out.push_str(&format!("{UNDIM}{MARKER}{pip}"));
            }
        } else if Some(i) == proj_idx {
            out.push_str(&format!("{UNDIM}{PROJ}{pip}"));
        } else if i < filled {
            let (r, g, b) = pip_colors[i];
            out.push_str(&format!("{UNDIM}\x1b[38;2;{r};{g};{b}m{pip}"));
        } else {
            out.push_str(&format!("{MUTED}{pip}"));
        }
    }
    out.push_str(RST);
    out
}

fn parse_int_prefix(s: &str) -> i32 {
    s.split('.').next().unwrap_or("0").parse().unwrap_or(0)
}

fn str_at(v: &Value, path: &[&str]) -> String {
    let mut cur = v;
    for k in path {
        cur = match cur.get(k) {
            Some(v) => v,
            None => return String::new(),
        };
    }
    match cur {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}

fn last_two_components_with_home(p: &str) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let shown = if !home.is_empty() && p.starts_with(&home) {
        let rel = &p[home.len()..];
        if rel.is_empty() {
            "~".to_string()
        } else {
            format!("~{rel}")
        }
    } else {
        p.to_string()
    };
    let parts: Vec<&str> = shown.split('/').filter(|s| !s.is_empty()).collect();
    if shown.starts_with('~') {
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

fn load_git_cache() -> HashMap<String, String> {
    git_data::load_cache()
}

fn read_advisor_name() -> String {
    let path = PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".claude/settings.json");
    let content = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    let v: Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return String::new(),
    };
    v.get("advisorModel").and_then(|x| x.as_str()).map(String::from).unwrap_or_default()
}
