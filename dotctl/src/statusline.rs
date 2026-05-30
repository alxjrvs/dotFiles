// statusline subcommand — Rust port of dot-claude/statusline-command.sh.
//
// Reads Claude statusline JSON from stdin; refreshes git cache; emits a
// 3–5 line plain-ASCII statusline with colored git values + progress
// bars for context window + Pro/Max rate-limit windows.
//
// Layout (line-1 git keys use Nerd Font glyphs; branch/PR are OSC8 links):
//   Line 1: repo/dir [ branch] [ name] [ #N: state] [C: counters]
//   Line 2: [M: model] [A: advisor] [E: effort] [$cost ($/h) · today $X] [+N/-M]
//   Line 3: CTX [bar w/ amber autocompact-threshold cell] N% [AC] [200k+]
//   Line 4: 5h  [bar] N% [time left] [delta]
//   Line 5: 7d  [bar] N% [time left] [delta]

use anyhow::Result;
use chrono::Local;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Read};
use std::path::{Path, PathBuf};
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
// Autocompact threshold cell on the CTX bar — amber-orange, distinct from
// the blue MARKER (rate-window clock) and the yellow PROJ (burn projection).
const AUTOCOMPACT: &str = "\x1b[38;2;255;128;0m";

// Nerd Font glyphs for line-1 git keys (escape form — Write/Edit strips raw
// codepoints, see CLAUDE.md). Swap these consts to retaste the icons.
const GLYPH_BRANCH: &str = "\u{e0a0}"; // powerline branch
const GLYPH_WORKTREE: &str = "\u{f0e8}"; // fa sitemap — branched workspace
const GLYPH_PR: &str = "\u{f407}"; // octicon git-pull-request

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

    let session_id = str_at(&payload, &["session_id"]);
    let used_pct = str_at(&payload, &["context_window", "used_percentage"]);
    let worktree_name_input = str_at(&payload, &["worktree", "name"]);
    let project_dir = str_at(&payload, &["workspace", "project_dir"]);
    let cwd_input = str_at(&payload, &["workspace", "current_dir"]);
    let model_name = str_at(&payload, &["model", "display_name"]);
    let effort_level = str_at(&payload, &["effort", "level"]);
    let cost_usd = str_at(&payload, &["cost", "total_cost_usd"]);
    let duration_ms = str_at(&payload, &["cost", "total_duration_ms"]).parse::<i64>().unwrap_or(0);
    let lines_added = str_at(&payload, &["cost", "total_lines_added"]).parse::<i64>().unwrap_or(0);
    let lines_removed = str_at(&payload, &["cost", "total_lines_removed"]).parse::<i64>().unwrap_or(0);
    let pr_number = str_at(&payload, &["pr", "number"]);
    let pr_state = str_at(&payload, &["pr", "review_state"]);
    let exceeds_200k = payload.get("exceeds_200k_tokens").and_then(|v| v.as_bool()).unwrap_or(false);
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
        // OSC8-link the branch to its tree view when we know the repo URL.
        let b_disp = if !repo_url.is_empty() && !branch.is_empty() {
            format!("\x1b]8;;{repo_url}/tree/{branch}\x07{b}\x1b]8;;\x07")
        } else {
            b
        };
        line1.push_str(&format!(" {MUTED}[{RST}{BLUE}{GLYPH_BRANCH} {b_disp}{MUTED}]{RST}"));
    }

    let wt = if !worktree_name_input.is_empty() {
        worktree_name_input.clone()
    } else {
        git.get("GIT_WORKTREE_NAME").cloned().unwrap_or_default()
    };
    if !wt.is_empty() {
        line1.push_str(&format!(" {MUTED}[{RST}{MAGENTA}{GLYPH_WORKTREE} {wt}{MUTED}]{RST}"));
    }

    // PR (statusLine `pr` object — present only when the branch has a PR).
    // review_state colored by outcome; bare `#N` when state is unknown.
    if !pr_number.is_empty() {
        // OSC8-link the PR glyph+number straight to the PR page.
        let pr_id = if !repo_url.is_empty() {
            format!("\x1b]8;;{repo_url}/pull/{pr_number}\x07{GLYPH_PR} #{pr_number}\x1b]8;;\x07")
        } else {
            format!("{GLYPH_PR} #{pr_number}")
        };
        if pr_state.is_empty() {
            line1.push_str(&format!(" {MUTED}[{RST}{CYAN}{pr_id}{MUTED}]{RST}"));
        } else {
            let c = pr_state_color(&pr_state);
            line1.push_str(&format!(
                " {MUTED}[{RST}{CYAN}{pr_id}: {c}{pr_state}{MUTED}]{RST}"
            ));
        }
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
        // Append within-session burn rate ($/h) once the session is long
        // enough for it to be meaningful (reuses no external data).
        let mut money = match format_burn_rate(&cost_usd, duration_ms) {
            Some(rate) => format!("{cost_display} ({rate})"),
            None => cost_display,
        };
        // Cross-session spend for today. Always record this session's latest
        // cost (so concurrent sessions can see our contribution); only render
        // the total when *other* sessions added to it — else it just echoes
        // this session's cost.
        let cost_self = cost_usd.parse::<f64>().unwrap_or(0.0);
        if let Some(day) = daily_cost_total(&session_id, &cost_usd) {
            if day > cost_self + 0.005 {
                money.push_str(&format!("{MUTED} · today {RST}{GREEN}${day:.2}"));
            }
        }
        line2.push_str(&format!("{MUTED}[{RST}{GREEN}{money}{MUTED}]{RST}"));
    }
    // Lines churned this session (cost.total_lines_added/removed).
    if lines_added > 0 || lines_removed > 0 {
        if !line2.is_empty() {
            line2.push(' ');
        }
        line2.push_str(&format!(
            "{MUTED}[{RST}{GREEN}+{lines_added}{MUTED}/{RST}{RED}-{lines_removed}{MUTED}]{RST}"
        ));
    }
    if !line2.is_empty() {
        println!("{line2}");
    }

    // ── Line 3: CTX bar ───────────────────────────────────────────────
    let used_int = parse_int_prefix(&used_pct);
    let ac = autocompact_threshold();
    // Autocompact threshold rendered as a marker cell (amber) so the
    // compaction wall is visible before you hit it — mirrors the rate-window
    // clock pip, but in AUTOCOMPACT color.
    let ctx_bar = render_bar(used_int, Some(ac), None, cols, AUTOCOMPACT);
    let mut ctx_warn = String::new();
    // Crossed the autocompact line: amber AC tag.
    if used_int >= ac {
        ctx_warn.push_str(&format!(" {AUTOCOMPACT}AC{RST}"));
    }
    // exceeds_200k_tokens: flags crossing the 200k threshold (relevant on
    // 1M-context models, where % can still be low). Bold-red marker.
    if exceeds_200k {
        ctx_warn.push_str(&format!(" {BOLD}{RED}200k+{RST}"));
    }
    println!(
        "{MUTED}{:<3}{RST} {ctx_bar} {MUTED}{:3}%{RST}{ctx_warn}",
        "CTX", used_int
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

    let bar = render_bar(pct, Some(clock_pct), proj_pct, cols, MARKER);
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

fn render_bar(pct: i32, marker_pct: Option<i32>, proj_pct: Option<i32>, cols: Option<usize>, marker_color: &str) -> String {
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
                out.push_str(&format!("{UNDIM}{marker_color}{pip}"));
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

/// Within-session burn rate ($/h) from session cost + duration — no external
/// data. Returns None until the session has run ≥60s (rate is noise before
/// that) or if cost is zero/unparseable.
fn format_burn_rate(cost_str: &str, duration_ms: i64) -> Option<String> {
    let cost = cost_str.parse::<f64>().ok()?;
    if cost <= 0.0 || duration_ms < 60_000 {
        return None;
    }
    let hours = duration_ms as f64 / 3_600_000.0;
    Some(format!("${:.2}/h", cost / hours))
}

/// Color for a PR `review_state`, case-insensitive. Unknown states fall back
/// to MUTED so a new/renamed state still renders (just uncolored).
fn pr_state_color(state: &str) -> &'static str {
    match state.to_ascii_lowercase().as_str() {
        "approved" => GREEN,
        "changes_requested" => RED,
        "review_required" | "pending" => YELLOW,
        "commented" => CYAN,
        _ => MUTED,
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

/// Context % at which Claude Code triggers autocompact. Read from the
/// `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var (set in settings.json `env`,
/// inherited by the statusline subprocess); falls back to 80 when unset or
/// out of range.
fn autocompact_threshold() -> i32 {
    std::env::var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE")
        .ok()
        .and_then(|s| s.trim().parse::<i32>().ok())
        .filter(|p| (1..=100).contains(p))
        .unwrap_or(80)
}

/// `~/.claude/state` — shared journal dir (also written by hook::stop).
fn state_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".claude/state")
}

/// Record this session's latest cost under today's date dir and return the
/// day's total across all sessions (None when `cost_usd` is unparseable or
/// negative). Thin wrapper over `record_and_sum` for HOME/date lookup.
fn daily_cost_total(session_id: &str, cost_usd: &str) -> Option<f64> {
    let date = Local::now().format("%Y-%m-%d").to_string();
    record_and_sum(&state_dir().join("cost"), &date, session_id, cost_usd)
}

/// Write `<cost_root>/<date>/<session_id>` with this session's latest cost and
/// return the sum across that date dir. One file per session (keyed by id) so
/// concurrent background sessions never clobber a shared file. Split from the
/// HOME/date lookup so it's testable against a tempdir.
fn record_and_sum(cost_root: &Path, date: &str, session_id: &str, cost_usd: &str) -> Option<f64> {
    let cost = cost_usd.parse::<f64>().ok()?;
    if cost < 0.0 {
        return None;
    }
    let dir = cost_root.join(date);
    if !session_id.is_empty() {
        let _ = std::fs::create_dir_all(&dir);
        // Defensive: keep the id filesystem-safe.
        let fname = session_id.replace(['/', '\\', '.'], "_");
        let _ = std::fs::write(dir.join(fname), format!("{cost}"));
    }
    Some(sum_cost_dir(&dir))
}

/// Sum every per-session cost file in `dir` (today's latest costs).
fn sum_cost_dir(dir: &Path) -> f64 {
    let mut total = 0.0;
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            if let Ok(s) = std::fs::read_to_string(e.path()) {
                if let Ok(v) = s.trim().parse::<f64>() {
                    if v >= 0.0 {
                        total += v;
                    }
                }
            }
        }
    }
    total
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
    fn format_burn_rate_computes_dollars_per_hour() {
        // $0.60 over 1h → $0.60/h; $0.30 over 30m → $0.60/h.
        assert_eq!(format_burn_rate("0.60", 3_600_000).as_deref(), Some("$0.60/h"));
        assert_eq!(format_burn_rate("0.30", 1_800_000).as_deref(), Some("$0.60/h"));
    }

    #[test]
    fn format_burn_rate_suppressed_when_premature_or_free() {
        assert_eq!(format_burn_rate("0.50", 59_000), None); // <60s: too noisy
        assert_eq!(format_burn_rate("0", 3_600_000), None); // no spend
        assert_eq!(format_burn_rate("abc", 3_600_000), None); // unparseable
    }

    #[test]
    fn pr_state_color_maps_known_states_case_insensitively() {
        assert_eq!(pr_state_color("approved"), GREEN);
        assert_eq!(pr_state_color("CHANGES_REQUESTED"), RED);
        assert_eq!(pr_state_color("review_required"), YELLOW);
        assert_eq!(pr_state_color("commented"), CYAN);
        assert_eq!(pr_state_color("something_new"), MUTED);
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
        let s = render_bar(0, None, None, None, MARKER);
        // 30 pips of any color; render produces escape-prefixed chars per pip.
        // Easier check: count fill chars + empty chars.
        let fill = s.matches(PIP_FILL).count();
        let empty = s.matches(PIP_EMPTY).count();
        assert_eq!(fill + empty, DEFAULT_PIP_COUNT);
        assert_eq!(fill, 0);
    }

    #[test]
    fn render_bar_full_pct_fills_all_pips() {
        let s = render_bar(100, None, None, None, MARKER);
        let fill = s.matches(PIP_FILL).count();
        let empty = s.matches(PIP_EMPTY).count();
        assert_eq!(fill + empty, DEFAULT_PIP_COUNT);
        assert_eq!(empty, 0);
    }

    #[test]
    fn render_bar_pct_one_lights_at_least_one_pip() {
        let s = render_bar(1, None, None, None, MARKER);
        assert!(s.contains(PIP_FILL));
    }

    #[test]
    fn render_bar_negative_pct_clamps_to_zero() {
        let s = render_bar(-50, None, None, None, MARKER);
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

    #[test]
    fn render_bar_marker_uses_supplied_color() {
        // The marker pip must be drawn in the passed color, not hard-coded MARKER.
        let s = render_bar(0, Some(50), None, None, AUTOCOMPACT);
        assert!(s.contains(AUTOCOMPACT));
        assert!(!s.contains(MARKER));
    }

    #[test]
    fn autocompact_threshold_reads_env_and_clamps() {
        let prior = std::env::var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE").ok();
        std::env::set_var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "80");
        assert_eq!(autocompact_threshold(), 80);
        // Out-of-range and garbage fall back to the 80 default.
        std::env::set_var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "0");
        assert_eq!(autocompact_threshold(), 80);
        std::env::set_var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "abc");
        assert_eq!(autocompact_threshold(), 80);
        std::env::remove_var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE");
        assert_eq!(autocompact_threshold(), 80);
        if let Some(v) = prior {
            std::env::set_var("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", v);
        }
    }

    #[test]
    fn sum_cost_dir_totals_per_session_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("sess-a"), "1.50").unwrap();
        std::fs::write(dir.path().join("sess-b"), "0.25\n").unwrap();
        // Garbage and negatives are ignored, not fatal.
        std::fs::write(dir.path().join("sess-c"), "nope").unwrap();
        std::fs::write(dir.path().join("sess-d"), "-9").unwrap();
        let total = sum_cost_dir(dir.path());
        assert!((total - 1.75).abs() < 1e-9, "got {total}");
    }

    #[test]
    fn sum_cost_dir_missing_dir_is_zero() {
        assert_eq!(sum_cost_dir(Path::new("/nonexistent/cost/dir")), 0.0);
    }

    #[test]
    fn record_and_sum_overwrites_self_and_aggregates() {
        let root = tempfile::tempdir().unwrap();
        let date = "2026-05-29";
        // Records own cost; with no other sessions the total equals self.
        let t = record_and_sum(root.path(), date, "session-xyz", "2.00").unwrap();
        assert!((t - 2.00).abs() < 1e-9, "got {t}");
        // Re-recording the same session overwrites (latest wins), not additive.
        let t2 = record_and_sum(root.path(), date, "session-xyz", "3.00").unwrap();
        assert!((t2 - 3.00).abs() < 1e-9, "got {t2}");
        // A second concurrent session adds to the day's total.
        let t3 = record_and_sum(root.path(), date, "session-abc", "1.50").unwrap();
        assert!((t3 - 4.50).abs() < 1e-9, "got {t3}");
        // Unparseable and negative costs → None.
        assert_eq!(record_and_sum(root.path(), date, "session-xyz", "abc"), None);
        assert_eq!(record_and_sum(root.path(), date, "session-xyz", "-1"), None);
    }
}
