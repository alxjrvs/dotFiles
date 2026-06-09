# tests/bats/helpers.bash — shared helpers for the bats suites.
# Loaded via `load 'helpers'` at the top of each .bats file.

# git hooks inherit repo-context env from the invoking git process:
# `git push` exports GIT_DIR (et al) into lefthook pre-push, which would
# point every throwaway `git -C <tmp> init` at the REAL repo's git dir.
# Call first in every setup() so suites behave identically under git
# hooks and direct runs.
scrub_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_PREFIX
}
