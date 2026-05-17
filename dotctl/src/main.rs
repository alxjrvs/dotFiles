// dotctl — one-stop dotfiles installer + hot-path utility binary.
//
// Primary identity: syncing manager (`dotctl sync`, `dotctl update`,
// `dotctl doctor`). Secondary: hot-path subcommands (git-data, hook,
// statusline, prompt-render) consumed by the prompt, statusline, and
// Claude Code hooks.

use clap::{Parser, Subcommand};

mod doctor;
mod git_data;
mod hook;
mod sync;

#[derive(Parser)]
#[command(name = "dotctl", version, about = "alxjrvs/dotFiles installer + hot-path utility")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Install/sync the dotfiles environment to the current machine.
    /// Idempotent — safe to run anytime. Installs Homebrew, mise tools,
    /// sheldon, gh extensions, fzf, lefthook, claude CLI; applies macOS
    /// defaults; creates symlinks.
    Sync {
        /// Run brew update + upgrade + cleanup (slow).
        #[arg(long)]
        upgrade: bool,
        /// Comma-separated section tag(s) to run. Default = everything.
        /// Tags: brew mise sheldon symlinks claude fzf gh dotctl git
        ///       shell ssh ghostty bat atuin lazygit zsh git-hooks
        ///       lefthook health macos linux
        #[arg(long)]
        only: Option<String>,
        /// Auto-overwrite symlink conflicts (mv existing to .bak, then link).
        #[arg(short = 'f')]
        force: bool,
        /// Auto-skip symlink conflicts.
        #[arg(short = 's')]
        skip: bool,
    },

    /// Bump everything to current — equivalent to `dotctl sync --upgrade`
    /// (runs brew update/upgrade/cleanup before brew bundle + mise install
    /// + sheldon lock --update).
    Update,

    /// Read-only health check: tool presence, symlink integrity, drift.
    /// Exits non-zero on missing tools (warnings on symlink drift).
    Doctor,

    /// Gather git state and write the shell-sourceable cache file.
    /// Hot-path: called from the zsh prompt, Claude statusline, and
    /// UserPromptSubmit hook.
    GitData,

    /// Render the zsh prompt from cached git data.
    /// NOT YET IMPLEMENTED — port of zsh/50-prompt.zsh. Tracking: see
    /// dotctl/README.md roadmap (Phase 4).
    PromptRender,

    /// Render the Claude Code statusline from JSON on stdin.
    /// NOT YET IMPLEMENTED — port of dot-claude/statusline-command.sh.
    /// Tracking: see dotctl/README.md roadmap (Phase 4).
    Statusline,

    /// Dispatch a Claude Code hook event. Event name maps 1:1 to the
    /// bash hook file it replaces (kebab-case, without `.sh`).
    Hook { event: String },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Sync { upgrade, only, force, skip } => {
            let mode = if force {
                sync::LinkMode::Overwrite
            } else if skip {
                sync::LinkMode::Skip
            } else {
                sync::LinkMode::Interactive
            };
            sync::run(only.as_deref(), upgrade, mode)
        }
        Command::Update => sync::update(),
        Command::Doctor => doctor::run(),
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
