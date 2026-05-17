// dotctl — hot-path utility binary for the dotfiles repo.
//
// Consolidates the bash hot path (scripts/git-data.sh, prompt render,
// dot-claude/statusline-command.sh, dot-claude/hooks/*.sh) into one
// static Rust binary. Each subcommand has a 1:1 successor in the bash
// it's replacing, so output format stays compatible during migration.

use clap::{Parser, Subcommand};

mod git_data;
mod hook;

#[derive(Parser)]
#[command(name = "dotctl", version, about = "alxjrvs/dotFiles hot-path utility")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Gather git state and write the shell-sourceable cache file.
    /// Drop-in successor to scripts/git-data.sh — same cache path, same
    /// variable names, same file format.
    GitData,

    /// Render the zsh prompt from cached git data.
    /// NOT YET IMPLEMENTED — port of the powerline rendering in
    /// zsh/50-prompt.zsh. Tracking: see dotctl/README.md roadmap.
    PromptRender,

    /// Render the Claude Code statusline from JSON on stdin.
    /// NOT YET IMPLEMENTED — port of dot-claude/statusline-command.sh.
    /// Tracking: see dotctl/README.md roadmap.
    Statusline,

    /// Dispatch a Claude Code hook event.
    /// Event name maps 1:1 to the bash hook file it replaces (kebab-case,
    /// without `.sh`): lock-file-guard, policy-guard, format-on-save,
    /// trim-bash-output, session-start, user-prompt-submit, cwd-changed,
    /// pre-compact, permission-denied.
    Hook {
        event: String,
    },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::GitData => git_data::run(),
        Command::PromptRender => {
            eprintln!("dotctl prompt-render: not yet implemented — see dotctl/README.md roadmap");
            std::process::exit(2);
        }
        Command::Statusline => {
            eprintln!("dotctl statusline: not yet implemented — see dotctl/README.md roadmap");
            std::process::exit(2);
        }
        Command::Hook { event } => hook::run(&event),
    }
}
