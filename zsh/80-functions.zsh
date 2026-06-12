# Run a command with secrets injected by 1Password CLI.
# Usage: op-run npm publish
# Resolves op:// references at exec time; nothing sensitive in shell env.
# Masking is left ON (no --no-masking): the child process still receives the
# real resolved value, but 1Password redacts it from the child's stdout/stderr,
# so secrets don't land in command output an agent/transcript could capture.
op-run() {
  command -v op &> /dev/null || {
    echo "op (1Password CLI) not installed"
    return 1
  }
  op run -- "$@"
}
