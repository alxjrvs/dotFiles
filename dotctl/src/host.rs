// host — per-host identification for multi-Mac overlays.
//
// The dotfiles owner runs two Macs (M3 Air + M2 Pro). This module
// decides which "host class" the current machine belongs to so
// macos_defaults, the Brewfile, and any future per-host wiring can
// pick the right variant. The classifier is intentionally generous
// (hostname substring match) so renames don't break detection.
//
// Override for testing the OTHER host's config locally:
//   DOTCTL_HOST=pro dotctl sync --only=macos
//   dotctl sync --host=air  (CLI flag sets the env var for this run)
//
// Detection cost: one `scutil --get LocalHostName` subprocess once
// per run, cached in OnceLock.

use std::process::Command;
use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostId {
    Air,
    Pro,
    Unknown,
}

impl HostId {
    pub fn as_str(self) -> &'static str {
        match self {
            HostId::Air => "air",
            HostId::Pro => "pro",
            HostId::Unknown => "unknown",
        }
    }

    pub fn from_str(s: &str) -> HostId {
        match s.to_ascii_lowercase().as_str() {
            "air" => HostId::Air,
            "pro" => HostId::Pro,
            _ => HostId::Unknown,
        }
    }
}

static CURRENT: OnceLock<HostId> = OnceLock::new();

pub fn current() -> HostId {
    *CURRENT.get_or_init(detect)
}

fn detect() -> HostId {
    if let Ok(forced) = std::env::var("DOTCTL_HOST") {
        if !forced.is_empty() {
            return HostId::from_str(&forced);
        }
    }
    let hostname = local_host_name().unwrap_or_default();
    classify(&hostname)
}

fn classify(hostname: &str) -> HostId {
    let lower = hostname.to_ascii_lowercase();
    // Order matters: "macbook-pro" contains both "macbook" and "pro";
    // checking pro first is fine but if a host had both substrings
    // we'd want a more specific match. Today's two hosts are clearly
    // disjoint (Air vs Pro) so substring is enough.
    if lower.contains("air") {
        HostId::Air
    } else if lower.contains("pro") {
        HostId::Pro
    } else {
        HostId::Unknown
    }
}

fn local_host_name() -> Option<String> {
    let out = Command::new("scutil")
        .args(["--get", "LocalHostName"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let name = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_matches_air_hostnames() {
        assert_eq!(classify("Alexs-MacBook-Air"), HostId::Air);
        assert_eq!(classify("jarvis-air"), HostId::Air);
        assert_eq!(classify("AIR"), HostId::Air);
    }

    #[test]
    fn classify_matches_pro_hostnames() {
        assert_eq!(classify("Alexs-Mac-Pro"), HostId::Pro);
        assert_eq!(classify("jarvis-macbook-pro"), HostId::Pro);
    }

    #[test]
    fn classify_unknown_for_neither() {
        assert_eq!(classify("foobar"), HostId::Unknown);
        assert_eq!(classify(""), HostId::Unknown);
    }

    #[test]
    fn from_str_round_trips_as_str() {
        for h in [HostId::Air, HostId::Pro, HostId::Unknown] {
            assert_eq!(HostId::from_str(h.as_str()), h);
        }
    }

    #[test]
    fn from_str_is_case_insensitive() {
        assert_eq!(HostId::from_str("AIR"), HostId::Air);
        assert_eq!(HostId::from_str("Pro"), HostId::Pro);
    }
}
