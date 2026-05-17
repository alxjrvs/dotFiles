# Files we lint by default. dot-claude/* is owned separately - lint-all sweeps it.
SHELL_FILES := sync.sh install/lib.sh $(wildcard install/[0-9][0-9]-*.sh) scripts/git-data.sh scripts/theme.sh git-hooks/pre-commit

DOT_CLAUDE_SHELL := $(wildcard dot-claude/hooks/*.sh) dot-claude/statusline-command.sh

.PHONY: help sync upgrade doctor lint lint-all fmt
.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  sync       Run ./sync.sh (config + symlinks, no brew upgrade)"
	@echo "  upgrade    Run ./sync.sh --upgrade (brew update + upgrade + cleanup)"
	@echo "  doctor     Run ./sync.sh --only=health"
	@echo "  lint       shellcheck on tracked shell scripts (excludes dot-claude/)"
	@echo "  lint-all   shellcheck on everything including dot-claude/"
	@echo "  fmt        shfmt -w on tracked shell scripts (2-space indent)"

sync:
	./sync.sh

upgrade:
	./sync.sh --upgrade

doctor:
	./sync.sh --only=health

lint:
	shellcheck -x $(SHELL_FILES)

lint-all:
	shellcheck -x $(SHELL_FILES) $(DOT_CLAUDE_SHELL)

fmt:
	shfmt -w -i 2 -ci -sr $(SHELL_FILES)
