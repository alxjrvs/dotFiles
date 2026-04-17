---
name: block-ccusage-limits
enabled: true
event: file
action: block
conditions:
  - field: file_path
    operator: regex_match
    pattern: ccusage/limits\.json$
---

**Blocked: ccusage/limits.json is personal data**

This file is gitignored and holds per-account token caps. It must only be edited by the user directly.

If the user has explicitly asked for a change, tell them to edit it themselves, or ask them to disable this rule.
