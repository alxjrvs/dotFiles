// macos_defaults — typed table of macOS user defaults that dotctl manages,
// plus apply + drift-check helpers.
//
// Replaces the inline `defaults write` calls that used to live in
// sync.rs::step_macos. The typed table makes:
//
//   1. `dotctl sync --only=macos` keep applying the writes (idempotent
//      since macOS `defaults` collapses repeated writes).
//   2. `dotctl doctor` able to surface drift via `defaults read` of each
//      managed key. A change made via System Settings now shows up as
//      a warning instead of silently disagreeing with the repo.
//
// Adding a new default: append to SHARED, or to AIR_OVERLAY / PRO_OVERLAY
// if it's host-specific. Decide kind (Bool/Int/Float/
// String), domain, key, raw write-arg. The expected_read() helper
// normalizes that value back to the string `defaults read` would emit
// (notably: bool "true" → "1") for comparison.

use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DefaultKind {
    Bool,
    Int,
    Float,
    // No SHARED entry uses String today (screencapture-location is
    // dynamic and handled inline in `apply`). Kept so the typed model
    // covers the full `defaults write` surface for future entries.
    #[allow(dead_code)]
    String,
}

#[derive(Debug, Clone)]
pub struct MacosDefault {
    pub domain: &'static str,
    pub key: &'static str,
    pub kind: DefaultKind,
    /// Value as passed to `defaults write -<kind> <raw>`. For Bool this is
    /// "true"/"false"; `defaults read` will report "1"/"0".
    pub raw: &'static str,
}

impl MacosDefault {
    pub fn kind_flag(&self) -> &'static str {
        match self.kind {
            DefaultKind::Bool => "-bool",
            DefaultKind::Int => "-int",
            DefaultKind::Float => "-float",
            DefaultKind::String => "-string",
        }
    }

    /// What `defaults read <domain> <key>` will print after this default is
    /// applied. Bools normalize to "1"/"0"; everything else round-trips.
    pub fn expected_read(&self) -> &str {
        match self.kind {
            DefaultKind::Bool => match self.raw {
                "true" | "TRUE" | "yes" | "YES" | "1" => "1",
                _ => "0",
            },
            _ => self.raw,
        }
    }
}

// Shared baseline that applies to every host. Per-host overlays below
// either ADD entries or OVERRIDE existing ones (matching domain+key).
pub const SHARED: &[MacosDefault] = &[
    // Fast key repeat (essential for vi/helix bindings)
    MacosDefault { domain: "NSGlobalDomain", key: "KeyRepeat", kind: DefaultKind::Int, raw: "2" },
    MacosDefault { domain: "NSGlobalDomain", key: "InitialKeyRepeat", kind: DefaultKind::Int, raw: "15" },
    MacosDefault { domain: "NSGlobalDomain", key: "ApplePressAndHoldEnabled", kind: DefaultKind::Bool, raw: "false" },
    // Finder
    MacosDefault { domain: "com.apple.finder", key: "AppleShowAllFiles", kind: DefaultKind::Bool, raw: "true" },
    MacosDefault { domain: "NSGlobalDomain", key: "AppleShowAllExtensions", kind: DefaultKind::Bool, raw: "true" },
    MacosDefault { domain: "com.apple.finder", key: "_FXShowPosixPathInWindowTitle", kind: DefaultKind::Bool, raw: "true" },
    // Trackpad
    MacosDefault { domain: "com.apple.AppleMultitouchTrackpad", key: "Clicking", kind: DefaultKind::Bool, raw: "true" },
    // Dock
    MacosDefault { domain: "com.apple.dock", key: "autohide", kind: DefaultKind::Bool, raw: "true" },
    MacosDefault { domain: "com.apple.dock", key: "autohide-delay", kind: DefaultKind::Float, raw: "0" },
    MacosDefault { domain: "com.apple.dock", key: "autohide-time-modifier", kind: DefaultKind::Float, raw: "0.3" },
    MacosDefault { domain: "com.apple.dock", key: "tilesize", kind: DefaultKind::Int, raw: "48" },
    // Text input — disable substitutions (autocorrect, dash/quote magic)
    MacosDefault { domain: "NSGlobalDomain", key: "NSAutomaticSpellingCorrectionEnabled", kind: DefaultKind::Bool, raw: "false" },
    MacosDefault { domain: "NSGlobalDomain", key: "NSAutomaticCapitalizationEnabled", kind: DefaultKind::Bool, raw: "false" },
    MacosDefault { domain: "NSGlobalDomain", key: "NSAutomaticPeriodSubstitutionEnabled", kind: DefaultKind::Bool, raw: "false" },
    MacosDefault { domain: "NSGlobalDomain", key: "NSAutomaticDashSubstitutionEnabled", kind: DefaultKind::Bool, raw: "false" },
    MacosDefault { domain: "NSGlobalDomain", key: "NSAutomaticQuoteSubstitutionEnabled", kind: DefaultKind::Bool, raw: "false" },
    // No .DS_Store noise on networked / USB volumes
    MacosDefault { domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", kind: DefaultKind::Bool, raw: "true" },
    MacosDefault { domain: "com.apple.desktopservices", key: "DSDontWriteUSBStores", kind: DefaultKind::Bool, raw: "true" },
];

// Per-host overlays. EMPTY by default — populate as you find genuinely
// per-host knobs. Examples: dock tilesize might be 48 on a 13" Air and
// 64 on a Pro; the trackpad doesn't exist on the Mac Pro; Hot Corner
// preferences vary by form factor. When an overlay entry's (domain, key)
// matches a SHARED entry, the overlay value wins.
pub const AIR_OVERLAY: &[MacosDefault] = &[];

pub const PRO_OVERLAY: &[MacosDefault] = &[];

/// Build the effective managed list for a given host by merging SHARED
/// with the per-host overlay. Overlay entries with the same (domain,
/// key) as SHARED overwrite the SHARED value; new (domain, key) pairs
/// are appended.
pub fn managed_for(host: crate::host::HostId) -> Vec<MacosDefault> {
    use crate::host::HostId;
    let overlay: &[MacosDefault] = match host {
        HostId::Air => AIR_OVERLAY,
        HostId::Pro => PRO_OVERLAY,
        HostId::Unknown => &[],
    };
    let mut merged: Vec<MacosDefault> = SHARED.to_vec();
    for o in overlay {
        if let Some(slot) = merged
            .iter_mut()
            .find(|d| d.domain == o.domain && d.key == o.key)
        {
            *slot = o.clone();
        } else {
            merged.push(o.clone());
        }
    }
    merged
}

/// Apply every managed default for the given host plus the dynamic screencapture-location
/// write (depends on $HOME, can't be a static entry). Restarts
/// SystemUIServer, Dock, Finder at the end. Returns the count of
/// defaults that wrote successfully.
pub fn apply(home: &Path, host: crate::host::HostId) -> u32 {
    let mut applied = 0u32;
    for d in managed_for(host).iter() {
        let status = Command::new("defaults")
            .args(["write", d.domain, d.key, d.kind_flag(), d.raw])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if matches!(status, Ok(s) if s.success()) {
            applied += 1;
        }
    }
    // Dynamic: screenshots directory + location
    let screenshots = home.join("Screenshots");
    let _ = std::fs::create_dir_all(&screenshots);
    if let Some(p) = screenshots.to_str() {
        let _ = Command::new("defaults")
            .args(["write", "com.apple.screencapture", "location", "-string", p])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    for svc in ["SystemUIServer", "Dock", "Finder"] {
        let _ = Command::new("killall")
            .arg(svc)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    applied
}

/// Read a single managed default's current value via `defaults read`.
/// Returns None if the key is unset or `defaults` failed.
pub fn read(d: &MacosDefault) -> Option<String> {
    let out = Command::new("defaults")
        .args(["read", d.domain, d.key])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Result of a drift audit. Each variant is a managed key categorized
/// by what the machine currently says about it.
#[derive(Debug)]
pub enum AuditResult {
    Match,
    Drift { expected: String, actual: String },
    Missing,
}

/// Audit every managed default for the given host. Returns a Vec
/// pairing each effective entry with its categorization. NB: returns
/// owned MacosDefault rather than &'static because the overlay merge
/// produces a Vec, not a static slice.
pub fn audit(host: crate::host::HostId) -> Vec<(MacosDefault, AuditResult)> {
    managed_for(host)
        .into_iter()
        .map(|d| {
            let result = match read(&d) {
                None => AuditResult::Missing,
                Some(actual) => {
                    let expected = d.expected_read();
                    if actual == expected {
                        AuditResult::Match
                    } else {
                        AuditResult::Drift {
                            expected: expected.to_string(),
                            actual,
                        }
                    }
                }
            };
            (d, result)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kind_flag_matches_defaults_cli_flag() {
        let make = |k| MacosDefault {
            domain: "x",
            key: "y",
            kind: k,
            raw: "z",
        };
        assert_eq!(make(DefaultKind::Bool).kind_flag(), "-bool");
        assert_eq!(make(DefaultKind::Int).kind_flag(), "-int");
        assert_eq!(make(DefaultKind::Float).kind_flag(), "-float");
        assert_eq!(make(DefaultKind::String).kind_flag(), "-string");
    }

    #[test]
    fn expected_read_normalizes_bool_truthy_to_1() {
        let make = |raw| MacosDefault {
            domain: "x",
            key: "y",
            kind: DefaultKind::Bool,
            raw,
        };
        assert_eq!(make("true").expected_read(), "1");
        assert_eq!(make("YES").expected_read(), "1");
        assert_eq!(make("1").expected_read(), "1");
    }

    #[test]
    fn expected_read_normalizes_bool_falsy_to_0() {
        let make = |raw| MacosDefault {
            domain: "x",
            key: "y",
            kind: DefaultKind::Bool,
            raw,
        };
        assert_eq!(make("false").expected_read(), "0");
        assert_eq!(make("0").expected_read(), "0");
        assert_eq!(make("anything-else").expected_read(), "0");
    }

    #[test]
    fn expected_read_passes_through_non_bool_values() {
        let make = |kind, raw| MacosDefault {
            domain: "x",
            key: "y",
            kind,
            raw,
        };
        assert_eq!(make(DefaultKind::Int, "42").expected_read(), "42");
        assert_eq!(make(DefaultKind::Float, "0.3").expected_read(), "0.3");
        assert_eq!(make(DefaultKind::String, "hi").expected_read(), "hi");
    }

    #[test]
    fn shared_table_is_nonempty_and_keys_unique() {
        assert!(!SHARED.is_empty());
        let mut keys: Vec<(&str, &str)> = SHARED.iter().map(|d| (d.domain, d.key)).collect();
        keys.sort();
        let before = keys.len();
        keys.dedup();
        assert_eq!(keys.len(), before, "duplicate (domain, key) in SHARED");
    }

    #[test]
    fn managed_for_unknown_host_is_shared() {
        let m = managed_for(crate::host::HostId::Unknown);
        assert_eq!(m.len(), SHARED.len());
        for (a, b) in m.iter().zip(SHARED.iter()) {
            assert_eq!(a.domain, b.domain);
            assert_eq!(a.key, b.key);
            assert_eq!(a.raw, b.raw);
        }
    }

    #[test]
    fn overlay_merge_overrides_in_place_and_appends_new() {
        // Real AIR_OVERLAY/PRO_OVERLAY are empty today; this synthetic
        // exercise pins the merge semantics so future entries behave.
        let base = vec![
            MacosDefault { domain: "x", key: "k1", kind: DefaultKind::Int, raw: "1" },
            MacosDefault { domain: "x", key: "k2", kind: DefaultKind::Int, raw: "2" },
        ];
        let overlay = &[
            MacosDefault { domain: "x", key: "k1", kind: DefaultKind::Int, raw: "99" },
            MacosDefault { domain: "y", key: "k3", kind: DefaultKind::Int, raw: "3" },
        ];
        let mut merged = base.clone();
        for o in overlay {
            if let Some(s) = merged.iter_mut().find(|d| d.domain == o.domain && d.key == o.key) {
                *s = o.clone();
            } else {
                merged.push(o.clone());
            }
        }
        assert_eq!(merged.len(), 3);
        assert_eq!(merged[0].raw, "99");
        assert_eq!(merged[1].raw, "2");
        assert_eq!(merged[2].domain, "y");
    }
}
