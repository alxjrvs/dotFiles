---
name: folded-over-cap
description: >-
  This description is deliberately written as a YAML folded block, because the
  single-line parser this fixture exists to regress scored such a block as
  exactly one word — the folded indicator itself — and therefore let an
  arbitrarily long description through the cap that exists precisely to stop
  it. Every skill description is loaded into the context of every session the
  user starts, which is the whole reason the cap was written, and the reason a
  gate that cannot read this text is worth nothing at all.
---

# folded-over-cap

Fixture, not a skill. Its description is a folded block well over the cap; the
gate must reject it. Lives under `scripts/tests/fixtures/` so neither
lefthook's `dot-claude/skills/*/SKILL.md` glob nor CI's `git ls-files` of the
same path can mistake it for a real skill.
