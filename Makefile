# Files we lint by default. dot-claude/* is owned separately - lint-all sweeps it.
SHELL_FILES := bootstrap.sh scripts/theme.sh git-hooks/pre-commit

DOT_CLAUDE_SHELL := dot-claude/statusline-command.sh

.PHONY: help sync update doctor lint lint-all fmt
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  sync       dotctl sync (idempotent install/resync, no brew upgrade)"
	@echo "  update     dotctl update (brew update + upgrade + cleanup + resync)"
	@echo "  doctor     dotctl doctor (read-only health check)"
	@echo "  lint       shellcheck on tracked shell scripts (excludes dot-claude/)"
	@echo "  lint-all   shellcheck on everything including dot-claude/"
	@echo "  fmt        shfmt -w on tracked shell scripts (2-space indent)"

sync:
	dotctl sync

update:
	dotctl update

doctor:
	dotctl doctor

lint:
	shellcheck -x $(SHELL_FILES)

lint-all:
	shellcheck -x $(SHELL_FILES) $(DOT_CLAUDE_SHELL)

fmt:
	shfmt -w -i 2 -ci -sr $(SHELL_FILES)
