---
name: unscoped-rule
---

# A rule with frontmatter but no `paths:`

Fixture for `scripts/tests/gates.sh`. It pins the failure `scripts/rules-scoped.sh`
exists to catch, and the reason that failure needs a gate at all: nothing about
this file looks wrong. It parses, it works, it applies — it is simply billed to
every request of every session, which is the one thing the rules directory exists
to avoid.
