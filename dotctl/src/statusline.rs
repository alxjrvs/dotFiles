// statusline subcommand — Rust port of dot-claude/statusline-command.sh.
//
// Reads Claude statusline JSON from stdin; refreshes git cache; emits a
// 3–5 line plain-ASCII statusline with colored git values + progress
// bars for context window + Pro/Max rate-limit windows.
//
// Layout:
//   Line 1: repo/dir [B: branch] [W: name] [C: counters]
//   Line 2: [M: model] [A: advisor] [E: effort] [$cost]   (optional)
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

/// Default pip count when terminal columns are unknown (pre-CC-v2.1.153
/// payloads don't include `columns`). Used as the cap for `pip_count_for_width`.
const DEFAULT_PIP_COUNT: usize = 30;
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
    let cost_usd = str_at(&payload, &["cost", "total_cost_usd"]);
    let five_pct = str_at(&payload, &["rate_limits", "five_hour", "used_percentage"]);
    let five_resets_at = str_at(&payload, &["rate_limits", "five_hour", "resets_at"]);
    let seven_pct = str_at(&payload, &["rate_limits", "seven_day", "used_percentage"]);
    let seven_resets_at = str_at(&payload, &["rate_limits", "seven_day", "resets_at"]);

    // Terminal width — CC v2.1.153+ pipes `columns` at top level (matches
    // the field subagentStatusLine has always received). Also check
    // `terminal.columns` per the proposal in issue #22115. None on older
    // versions; render_bar falls back to DEFAULT_PIP_COUNT.
    let cols: Option<usize> = payload
        .get("columns")
        .and_then(|v| v.as_u64())
        .or_else(|| payload.get("terminal").and_then(|t| t.get("columns")).and_then(|v| v.as_u64()))
        .map(|n| n as usize);

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
        line1.push_str(&format!(" {MUTED}[{RST}{BLUE}B: {b}{MUTED}]{RST}"));
    }

    let wt = if !worktree_name_input.is_empty() {
        worktree_name_input.clone()
    } else {
        git.get("GIT_WORKTREE_NAME").cloned().unwrap_or_default()
    };
    if !wt.is_empty() {
        line1.push_str(&format!(" {MUTED}[{RST}{MAGENTA}W: {wt}{MUTED}]{RST}"));
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
            " {MUTED}[C: {RST}{}{MUTED}]{RST}",
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
    let cost_display = format_cost(&cost_usd);
    if !cost_display.is_empty() {
        if !line2.is_empty() {
            line2.push(' ');
        }
        // GREEN signals money — distinct from the cyan model/effort keys.
        line2.push_str(&format!("{MUTED}[{RST}{GREEN}{cost_display}{MUTED}]{RST}"));
    }
    if !line2.is_empty() {
        println!("{line2}");
    }

    // ── Line 3: Ctx bar ───────────────────────────────────────────────
    let used_int = parse_int_prefix(&used_pct);
    let ctx_bar = render_bar(used_int, None, None, cols);
    println!(
        "{MUTED}{:<3}{RST} {ctx_bar} {MUTED}{:3}%{RST}",
        "Ctx", used_int
    );

    // ── Lines 4-5: rate-limit windows ─────────────────────────────────
    print_window(&five_pct, &five_resets_at, 300, "5h", cols);
    print_window(&seven_pct, &seven_resets_at, 10_080, "7d", cols);

    Ok(())
}

fn print_window(pct_str: &str, resets_at_str: &str, window_min: u64, label: &str, cols: Option<usize>) {
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

    let bar = render_bar(pct, Some(clock_pct), proj_pct, cols);
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

/// Discrete piecewise scale of bar width based on terminal columns.
/// Returns DEFAULT_PIP_COUNT when columns are unknown (pre-v2.1.153 CC,
/// or pipe context where the field wasn't populated).
///
/// Calibration: bar lines have ~20 chars of label+pct+brackets overhead.
/// We aim for the bar to consume roughly half the terminal width, capped.
fn pip_count_for_width(cols: Option<usize>) -> usize {
    match cols {
        None => DEFAULT_PIP_COUNT,
        Some(c) if c < 60 => 15,
        Some(c) if c < 90 => 20,
        Some(c) if c < 120 => 30,
        Some(c) if c < 160 => 40,
        Some(_) => 50,
    }
}

fn render_bar(pct: i32, marker_pct: Option<i32>, proj_pct: Option<i32>, cols: Option<usize>) -> String {
    let pip_count = pip_count_for_width(cols);
    let pct = pct.max(0);
    let mut filled = (pct as usize) * pip_count / 100;
    if filled > pip_count {
        filled = pip_count;
    }
    if pct > 0 && filled == 0 {
        filled = 1;
    }

    let (marker_idx, marker_expired): (Option<usize>, bool) = match marker_pct {
        Some(m) if m >= 100 => (Some(pip_count - 1), true),
        Some(m) => {
            let idx = (m.max(0) as usize) * pip_count / 100;
            (Some(idx.min(pip_count - 1)), false)
        }
        None => (None, false),
    };
    let proj_idx: Option<usize> = match proj_pct {
        Some(p) if (0..=100).contains(&p) => {
            let idx = (p as usize) * pip_count / 100;
            Some(idx.min(pip_count - 1))
        }
        _ => None,
    };

    // Pre-compute per-pip gradient color.
    let mut pip_colors: Vec<(u8, u8, u8)> = Vec::with_capacity(pip_count);
    for k in 0..pip_count {
        pip_colors.push(gradient_at((k as i32) * 10_000 / (pip_count as i32 - 1)));
    }

    let mut out = String::new();
    for i in 0..pip_count {
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

/// Format a USD session-cost string (CC's `cost.total_cost_usd`, e.g.
/// "0.4231") as "$0.42". Empty/unparseable/negative → "" so the segment is
/// skipped. $0.00 IS shown when the field is present (cost tracking is live).
fn format_cost(s: &str) -> String {
    match s.parse::<f64>() {
        Ok(v) if v >= 0.0 => format!("${v:.2}"),
        _ => String::new(),
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_int_prefix_strips_decimals() {
        assert_eq!(parse_int_prefix("42.7"), 42);
        assert_eq!(parse_int_prefix("100"), 100);
        assert_eq!(parse_int_prefix("0.0"), 0);
    }

    #[test]
    fn parse_int_prefix_returns_zero_on_garbage() {
        assert_eq!(parse_int_prefix(""), 0);
        assert_eq!(parse_int_prefix("abc"), 0);
        assert_eq!(parse_int_prefix("abc.7"), 0);
    }

    #[test]
    fn format_cost_rounds_to_two_decimals() {
        assert_eq!(format_cost("0.4231"), "$0.42");
        assert_eq!(format_cost("0.4271"), "$0.43");
        assert_eq!(format_cost("12"), "$12.00");
        assert_eq!(format_cost("3.5"), "$3.50");
    }

    #[test]
    fn format_cost_shows_zero_when_present() {
        // $0.00 is meaningful — cost tracking is active, just no spend yet.
        assert_eq!(format_cost("0"), "$0.00");
        assert_eq!(format_cost("0.0"), "$0.00");
    }

    #[test]
    fn format_cost_empty_on_missing_or_garbage() {
        // Missing field (str_at → "") and non-numeric input skip the segment.
        assert_eq!(format_cost(""), "");
        assert_eq!(format_cost("abc"), "");
        assert_eq!(format_cost("-1.0"), "");
    }

    #[test]
    fn str_at_handles_string_and_number_values() {
        // statusline::str_at coerces numbers to strings (distinct from hook::str_at).
        let v = json!({"a": {"b": "text", "c": 42}});
        assert_eq!(str_at(&v, &["a", "b"]), "text");
        assert_eq!(str_at(&v, &["a", "c"]), "42");
    }

    #[test]
    fn str_at_returns_empty_on_missing_or_object_leaf() {
        let v = json!({"a": {"b": "text"}});
        assert_eq!(str_at(&v, &["x"]), "");
        // Object leaf returns "" — statusline never wants the whole subtree.
        assert_eq!(str_at(&v, &["a"]), "");
    }

    #[test]
    fn last_two_components_with_home_substitutes_tilde() {
        let prior = std::env::var("HOME").ok();
        std::env::set_var("HOME", "/Users/jarvis");
        assert_eq!(last_two_components_with_home("/Users/jarvis/dotFiles"), "~/dotFiles");
        if let Some(v) = prior {
            std::env::set_var("HOME", v);
        }
    }

    #[test]
    fn last_two_components_truncates_deep_paths() {
        let prior = std::env::var("HOME").ok();
        std::env::set_var("HOME", "/Users/jarvis");
        assert_eq!(
            last_two_components_with_home("/Users/jarvis/code/work/proj"),
            "work/proj"
        );
        if let Some(v) = prior {
            std::env::set_var("HOME", v);
        }
    }

    #[test]
    fn last_two_components_handles_root() {
        std::env::set_var("HOME", "/nonexistent");
        // Two components: "tmp" + "x"
        assert_eq!(last_two_components_with_home("/tmp/x"), "tmp/x");
    }

    #[test]
    fn render_bar_zero_pct_emits_pip_count_chars() {
        let s = render_bar(0, None, None, None);
        // 30 pips of any color; render produces escape-prefixed chars per pip.
        // Easier check: count fill chars + empty chars.
        let fill = s.matches(PIP_FILL).count();
        let empty = s.matches(PIP_EMPTY).count();
        assert_eq!(fill + empty, DEFAULT_PIP_COUNT);
        assert_eq!(fill, 0);
    }

    #[test]
    fn render_bar_full_pct_fills_all_pips() {
        let s = render_bar(100, None, None, None);
        let fill = s.matches(PIP_FILL).count();
        let empty = s.matches(PIP_EMPTY).count();
        assert_eq!(fill + empty, DEFAULT_PIP_COUNT);
        assert_eq!(empty, 0);
    }

    #[test]
    fn render_bar_pct_one_lights_at_least_one_pip() {
        let s = render_bar(1, None, None, None);
        assert!(s.contains(PIP_FILL));
    }

    #[test]
    fn render_bar_negative_pct_clamps_to_zero() {
        let s = render_bar(-50, None, None, None);
        assert_eq!(s.matches(PIP_FILL).count(), 0);
    }

    #[test]
    fn gradient_at_endpoints_are_distinct() {
        let cold = gradient_at(0);
        let hot = gradient_at(10_000);
        assert_ne!(cold, hot);
        // Hot end should be brighter overall (warmer).
        assert!(hot.0 as u32 + hot.1 as u32 + hot.2 as u32 > cold.0 as u32 + cold.1 as u32 + cold.2 as u32);
    }
}
