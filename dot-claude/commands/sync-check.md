---
description: Audit dotfiles environment — thin wrapper over `dotctl doctor`
---

# /sync-check

Run `dotctl doctor` and surface the output. All the checks this command
used to perform — Brewfile drift, mise toolchain drift, gh auth, lefthook
hook installation, pueued liveness, macOS defaults drift, and symlink
integrity — now live inside the binary so they're available without a
Claude session (CI / pre-push hook / cold terminal).

## Steps

1. Run `dotctl doctor`.
2. Surface the output verbatim.
3. If doctor exits non-zero, suggest fixes from the warnings (most map
   to either `dotctl sync --only=<tag>`, `lefthook install`,
   `gh auth login`, `pueued -d`, or `mise install`).

## Why this is now thin

The audit + drift detection logic moved into `dotctl/src/doctor.rs`
during the doctor-expansion overhaul. Keeping `/sync-check` as a thin
wrapper preserves muscle memory; the substantive work lives in Rust
where it can be unit-tested and run anywhere.
