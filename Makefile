# Files we lint by default. dot-claude/* is owned separately - lint-all sweeps it.
SHELL_FILES := sync.sh scripts/git-data.sh scripts/theme.sh git-hooks/pre-commit

DOT_CLAUDE_SHELL := $(wildcard dot-claude/hooks/*.sh) dot-claude/statusline-command.sh

.PHONY: lint fmt help
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  lint   shellcheck on all tracked shell scripts"
	@echo "  fmt    shfmt -w on all tracked shell scripts (2-space indent)"

lint:
	shellcheck -x $(SHELL_FILES)

lint-all:
	shellcheck -x $(SHELL_FILES) $(DOT_CLAUDE_SHELL)

fmt:
	shfmt -w -i 2 -ci -sr $(SHELL_FILES)
