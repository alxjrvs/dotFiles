// subagent_statusline — emit a per-subagent JSON status line for CC's
// agent panel. Configured via the `subagentStatusLine` setting (undocumented
// in CC v2.1.150 as of 2026-05; schema inferred empirically by probing
// from a BG session — see ~/dotFiles/probes/subagent-statusline-probe.sh).
//
// Input (stdin JSON):
//   {
//     "session_id": "...",
//     "transcript_path": "...",
//     "cwd": "...",
//     "agent_type": "claude",
//     "columns": 168,
//     "tasks": [
//       {
//         "id": "agent-xyz",
//         "type": "local_agent",
//         "status": "running" | "complete" | ...,
//         "description": "...",
//         "label": "...",
//         "startTime": <epoch ms>,
//         "tokenCount": 1234,
//         "tokenSamples": [<numbers>],
//         "cwd": "..."
//       }, ...
//     ]
//   }
//
// Output (stdout JSON): best-guess schema based on field names extracted
// from the CC binary's error strings cluster (tokenText, queuedText,
// queuedCount, elapsed, tokenSamples, success/error/inactive):
//   {
//     "tasks": [
//       {
//         "id": "<same as input>",
//         "state": "success" | "error" | "inactive",
//         "tokenText": "1.2k",
//         "queuedText": "queued",
//         "queuedCount": 0,
//         "elapsed": "2m05s",
//         "tokenSamples": [<numbers>]
//       }, ...
//     ]
//   }
//
// The agent panel renders only in FOREGROUND `claude agents` sessions —
// BG sessions can confirm output is emitted but cannot visually verify
// the panel update. Iterate by opening `claude agents` after settings
// edits.

use anyhow::Result;
use serde_json::{json, Value};
use std::io::{self, Read, Write};

pub fn run() -> Result<()> {
    let mut buf = String::new();
    let _ = io::stdin().read_to_string(&mut buf);
    let input: Value = serde_json::from_str(&buf).unwrap_or(Value::Null);

    let tasks_in = input
        .get("tasks")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let mut tasks_out: Vec<Value> = Vec::with_capacity(tasks_in.len());
    for t in tasks_in {
        let id = t.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let status = t
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("running");
        let token_count = t
            .get("tokenCount")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let start_time = t
            .get("startTime")
            .and_then(|v| v.as_u64())
            .unwrap_or(now_ms);
        let token_samples = t
            .get("tokenSamples")
            .cloned()
            .unwrap_or_else(|| Value::Array(vec![]));

        let state = match status {
            "complete" | "completed" | "succeeded" | "success" => "success",
            "failed" | "error" => "error",
            "inactive" | "idle" => "inactive",
            _ => "success", // running / unknown → assume in progress, render as active
        };

        let elapsed_secs = now_ms.saturating_sub(start_time) / 1000;
        let elapsed = format_elapsed(elapsed_secs);
        let token_text = format_token_count(token_count);

        tasks_out.push(json!({
            "id": id,
            "state": state,
            "tokenText": token_text,
            "queuedText": "",
            "queuedCount": 0,
            "elapsed": elapsed,
            "tokenSamples": token_samples,
        }));
    }

    let out = json!({ "tasks": tasks_out });
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    writeln!(handle, "{out}")?;
    Ok(())
}

fn format_token_count(n: u64) -> String {
    if n < 1_000 {
        n.to_string()
    } else if n < 1_000_000 {
        format!("{:.1}k", (n as f64) / 1_000.0)
    } else {
        format!("{:.1}M", (n as f64) / 1_000_000.0)
    }
}

fn format_elapsed(secs: u64) -> String {
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        let m = secs / 60;
        let s = secs % 60;
        format!("{m}m{s:02}s")
    } else {
        let h = secs / 3600;
        let m = (secs % 3600) / 60;
        format!("{h}h{m:02}m")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_token_count_under_thousand_is_plain() {
        assert_eq!(format_token_count(0), "0");
        assert_eq!(format_token_count(42), "42");
        assert_eq!(format_token_count(999), "999");
    }

    #[test]
    fn format_token_count_thousands_compact() {
        assert_eq!(format_token_count(1_000), "1.0k");
        assert_eq!(format_token_count(12_345), "12.3k");
        assert_eq!(format_token_count(999_999), "1000.0k");
    }

    #[test]
    fn format_token_count_millions_compact() {
        assert_eq!(format_token_count(1_000_000), "1.0M");
        assert_eq!(format_token_count(2_500_000), "2.5M");
    }

    #[test]
    fn format_elapsed_seconds() {
        assert_eq!(format_elapsed(0), "0s");
        assert_eq!(format_elapsed(59), "59s");
    }

    #[test]
    fn format_elapsed_minutes_with_zero_padding() {
        assert_eq!(format_elapsed(60), "1m00s");
        assert_eq!(format_elapsed(125), "2m05s");
        assert_eq!(format_elapsed(3599), "59m59s");
    }

    #[test]
    fn format_elapsed_hours() {
        assert_eq!(format_elapsed(3600), "1h00m");
        assert_eq!(format_elapsed(7325), "2h02m");
    }
}
