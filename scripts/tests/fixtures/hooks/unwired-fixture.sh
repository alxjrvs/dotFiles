#!/usr/bin/env bash
# Fixture for scripts/tests/gates.sh: a guard sitting in a hooks directory that
# settings-guardrails.sh's wired_hooks() list does not name. Never executed —
# only its FILENAME matters, which is the whole point: an unwired guard is a
# file on disk that no gate mentions.
exit 0
