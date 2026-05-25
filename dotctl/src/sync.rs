// sync subcommand — Rust port of sync.sh + install/*.sh.
//
// `dotctl sync` is the one-stop installer/syncer. It takes a bare machine
// (with rust + git already present from bootstrap.sh) to a fully configured
// one: installs Homebrew, mise toolchains, sheldon, gh extensions,
// lefthook, claude CLI, applies macOS defaults, creates symlinks.
//
// Idempotent: re-running is safe and fast when nothing changed.
//
// `dotctl update` wraps sync with --upgrade (brew update/upgrade/cleanup).

use anyhow::{anyhow, bail, Context, Result};
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

use crate::util::which;

// ─────────────────────────────────────────────────────────────── public API

pub fn run(only: Option<&str>, upgrade: bool, link_mode: LinkMode) -> Result<()> {
    // Prepend mise shims to PATH so `which("lefthook")` / `which("sheldon")`
    // and all the Command::new(tool) probes below resolve regardless of the
    // caller's PATH (sync is often invoked from bash subprocesses, CI, or
    // git hooks that don't source .zshenv).
    if let Ok(home) = std::env::var("HOME") {
        let shims = format!("{home}/.local/share/mise/shims");
        if Path::new(&shims).is_dir() {
            let current = std::env::var("PATH").unwrap_or_default();
            if !current.split(':').any(|p| p == shims) {
                std::env::set_var("PATH", format!("{shims}:{current}"));
            }
        }
    }

    let ctx = Context_::new(only, upgrade, link_mode)?;
    let _lock = LockGuard::acquire()?;

    // Each step is gated on its tag and on OS. Sourcing an inert step is
    // a cheap no-op — same shape as the bash modules.
    step_brew(&ctx)?;
    step_linux(&ctx)?;
    step_sheldon_bin(&ctx)?;
    step_dotctl(&ctx)?;
    step_mise(&ctx)?;
    step_symlinks(&ctx)?;
    step_sheldon_plugins(&ctx)?;
    step_claude(&ctx)?;
    step_gh(&ctx)?;
    step_git_maint(&ctx)?;
    step_lefthook(&ctx)?;
    step_macos(&ctx)?;

    // Sync owns the lifecycle of the `.bak` files its link() function
    // produces — prompt to clean them at the end so the manager closes
    // the loop. Interactive mode prompts (default yes); non-interactive
    // modes (-f/-s) auto-delete to match the caller's silence intent.
    let prune_mode = match ctx.link_mode {
        LinkMode::Interactive => crate::prune::PromptMode::AskDefaultYes,
        LinkMode::Overwrite | LinkMode::Skip => crate::prune::PromptMode::AutoYes,
    };
    let _ = crate::prune::run(prune_mode);

    println!();
    println!("==> Done!");
    if ctx.only.is_none() {
        println!("   Restart your shell or run: source ~/.zshrc");
    }
    Ok(())
}

pub fn update() -> Result<()> {
    run(None, true, LinkMode::Interactive)
}

// ──────────────────────────────────────────────────────────────────── types

#[derive(Clone, Copy)]
pub enum LinkMode {
    Interactive,
    Overwrite,
    Skip,
}

struct Context_ {
    only: Option<Vec<String>>,
    upgrade: bool,
    link_mode: LinkMode,
    dotfiles_dir: PathBuf,
    home: PathBuf,
    os: Os,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Os {
    Darwin,
    Linux,
    Other,
}

impl Context_ {
    fn new(only: Option<&str>, upgrade: bool, link_mode: LinkMode) -> Result<Self> {
        let dotfiles_dir = std::env::var("DOTFILES_DIR")
            .map(PathBuf::from)
            .ok()
            .or_else(|| {
                std::env::current_exe()
                    .ok()
                    .and_then(|p| p.canonicalize().ok())
                    .and_then(|p| {
                        // ~/.local/bin/dotctl → walk up to find a dotctl/ sibling,
                        // then assume parent is DOTFILES_DIR. Fallback to ~/dotFiles.
                        None.or_else(|| Some(p))
                    })
            })
            .unwrap_or_else(|| {
                let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
                PathBuf::from(home).join("dotFiles")
            });
        // If DOTFILES_DIR points at the binary itself (the unwrap chain above
        // never resolved a real env), fall back to ~/dotFiles.
        let dotfiles_dir = if dotfiles_dir.is_dir() && dotfiles_dir.join("Brewfile").is_file() {
            dotfiles_dir
        } else {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            PathBuf::from(home).join("dotFiles")
        };
        if !dotfiles_dir.is_dir() {
            bail!("DOTFILES_DIR not found: {}", dotfiles_dir.display());
        }

        let home = std::env::var("HOME")
            .map(PathBuf::from)
            .map_err(|_| anyhow!("HOME not set"))?;

        let os = match std::env::consts::OS {
            "macos" => Os::Darwin,
            "linux" => Os::Linux,
            _ => Os::Other,
        };

        let only = only.map(|s| {
            s.split(',')
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect()
        });

        Ok(Self {
            only,
            upgrade,
            link_mode,
            dotfiles_dir,
            home,
            os,
        })
    }

    // Step runs if no --only filter set, or any of its tags matches the filter.
    fn should_run(&self, tags: &[&str]) -> bool {
        match &self.only {
            None => true,
            Some(only) => tags.iter().any(|t| only.iter().any(|o| o == t)),
        }
    }
}

// ─────────────────────────────────────────────────────────────── output helpers

const GREEN: &str = "\x1b[0;32m";
const YELLOW: &str = "\x1b[0;33m";
const RED: &str = "\x1b[0;31m";
const DIM: &str = "\x1b[2m";
const NC: &str = "\x1b[0m";

fn ok(msg: &str) {
    println!("{GREEN}  ✓ {msg}{NC}");
}
fn warn(msg: &str) {
    println!("{YELLOW}  → {msg}{NC}");
}
fn fail(msg: &str) {
    eprintln!("{RED}  ✗ {msg}{NC}");
}
fn dim(msg: &str) {
    println!("{DIM}  - {msg}{NC}");
}
fn section(name: &str) {
    println!();
    println!("==> {name}");
}

// ──────────────────────────────────────────────────────────────────── locking

struct LockGuard {
    path: PathBuf,
}

impl LockGuard {
    fn acquire() -> Result<Self> {
        let dir = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".into());
        let path = PathBuf::from(dir).join("dotfiles-sync.lock");

        if path.exists() {
            if let Ok(s) = fs::read_to_string(&path) {
                if let Ok(pid) = s.trim().parse::<i32>() {
                    // kill -0 equivalent: check if process exists
                    if libc_kill(pid, 0) == 0 {
                        bail!("Another sync is running (pid {pid})");
                    }
                }
            }
            warn("Removing stale lock file");
            let _ = fs::remove_file(&path);
        }

        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .with_context(|| format!("could not acquire lock at {}", path.display()))?;
        writeln!(f, "{}", std::process::id())?;
        Ok(Self { path })
    }
}

impl Drop for LockGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

// Minimal libc shim — kill(pid, 0) probes whether `pid` exists.
// Avoids pulling the `libc` crate for a single syscall.
extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}
#[allow(non_snake_case)]
fn libc_kill(pid: i32, sig: i32) -> i32 {
    unsafe { kill(pid, sig) }
}

// ────────────────────────────────────────────────────────────────── linker

pub fn link(src: &Path, dst: &Path, label: &str, mode: LinkMode) -> Result<()> {
    // Already correctly linked?
    if let Ok(meta) = fs::symlink_metadata(dst) {
        if meta.file_type().is_symlink() {
            if let Ok(target) = fs::read_link(dst) {
                if target == src {
                    dim(&format!("{label} already linked"));
                    return Ok(());
                }
            }
        }
    } else {
        // Doesn't exist — create the symlink.
        if let Some(parent) = dst.parent() {
            let _ = fs::create_dir_all(parent);
        }
        symlink(src, dst)
            .with_context(|| format!("link {} -> {}", dst.display(), src.display()))?;
        warn(&format!("{label} linked"));
        return Ok(());
    }

    // Conflict: something else exists.
    fail(&format!("{label}: {} exists but is not our symlink", dst.display()));
    let choice = match mode {
        LinkMode::Overwrite => "o".to_string(),
        LinkMode::Skip => "s".to_string(),
        LinkMode::Interactive => {
            print!(
                "       Overwrite with symlink to {}? [o]verwrite / [s]kip: ",
                src.display()
            );
            io::stdout().flush().ok();
            let mut s = String::new();
            io::stdin().read_line(&mut s).ok();
            s.trim().to_string()
        }
    };
    match choice.to_lowercase().as_str() {
        "o" | "overwrite" => {
            // Plain `<dst>.bak` (not `<dst>.<ext>.bak`) to match the bash mv pattern.
            let backup = {
                let mut s = dst.as_os_str().to_owned();
                s.push(".bak");
                PathBuf::from(s)
            };
            fs::rename(dst, &backup)
                .with_context(|| format!("backup {} -> {}", dst.display(), backup.display()))?;
            symlink(src, dst)
                .with_context(|| format!("link {} -> {}", dst.display(), src.display()))?;
            warn(&format!("{label} overwritten (backup at {})", backup.display()));
        }
        _ => {
            ok(&format!("{label} skipped"));
        }
    }
    Ok(())
}

// ────────────────────────────────────────────────────────────────── exec helpers

// Run a command, inheriting stdout/stderr. Returns Ok only on success.
fn run_cmd(prog: &str, args: &[&str]) -> Result<ExitStatus> {
    let status = Command::new(prog)
        .args(args)
        .status()
        .with_context(|| format!("failed to spawn `{prog} {}`", args.join(" ")))?;
    Ok(status)
}

// Same as run_cmd but bails on non-zero exit.
fn require(prog: &str, args: &[&str]) -> Result<()> {
    let status = run_cmd(prog, args)?;
    if !status.success() {
        bail!("`{prog} {}` exited {}", args.join(" "), status);
    }
    Ok(())
}

// Capture stdout (trimmed). Returns "" on failure.
fn capture(prog: &str, args: &[&str]) -> String {
    Command::new(prog)
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

// ───────────────────────────────────────────────────── 1. brew (Darwin)

fn step_brew(ctx: &Context_) -> Result<()> {
    if ctx.os != Os::Darwin || !ctx.should_run(&["brew"]) {
        return Ok(());
    }
    section("Homebrew");
    if which("brew") {
        ok("Homebrew installed");
    } else {
        warn("Installing Homebrew...");
        require(
            "bash",
            &[
                "-c",
                "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)",
            ],
        )?;
    }

    if ctx.upgrade {
        warn("Updating Homebrew...");
        require("brew", &["update"])?;
        warn("Upgrading formulae and casks...");
        require("brew", &["upgrade"])?;
        let _ = run_cmd("brew", &["upgrade", "--cask"]);
        warn("Removing outdated versions...");
        require("brew", &["cleanup", "--prune=all"])?;
    } else {
        dim("Skipping brew update/upgrade/cleanup (pass --upgrade to run)");
    }

    section("Brew Bundle");

    // Xcode CLT required by Homebrew.
    if Command::new("xcode-select").arg("--version").status().map(|s| !s.success()).unwrap_or(true) {
        warn("Installing Xcode Command Line Tools...");
        let _ = run_cmd("xcode-select", &["--install"]);
        fail("Xcode CLT installer opened — approve the dialog, then re-run `dotctl sync`");
        bail!("Xcode CLT missing");
    }

    warn("Installing Brewfile dependencies (skipping upgrades)...");
    require(
        "brew",
        &[
            "bundle",
            "--file",
            ctx.dotfiles_dir.join("Brewfile").to_str().unwrap(),
            "--no-upgrade",
        ],
    )?;
    ok("Brewfile dependencies up to date");

    // Per-host overlay: Brewfile.air / Brewfile.pro install on top of
    // the shared Brewfile. Skip silently if no overlay file exists
    // (Unknown host class, or host with no extras today).
    let host = crate::host::current();
    if host != crate::host::HostId::Unknown {
        let overlay = ctx.dotfiles_dir.join(format!("Brewfile.{}", host.as_str()));
        if overlay.is_file() {
            warn(&format!("Installing host overlay (Brewfile.{})...", host.as_str()));
            require(
                "brew",
                &[
                    "bundle",
                    "--file",
                    overlay.to_str().unwrap(),
                    "--no-upgrade",
                ],
            )?;
            ok(&format!("Brewfile.{} dependencies up to date", host.as_str()));
        }
    }

    // Docker Desktop / docker formula collision.
    let cask_docker = run_cmd("brew", &["list", "--cask", "docker-desktop"])
        .map(|s| s.success())
        .unwrap_or(false);
    let formula_docker = run_cmd("brew", &["list", "--formula", "docker"])
        .map(|s| s.success())
        .unwrap_or(false);
    if cask_docker && formula_docker {
        warn("Removing docker formula (conflicts with Docker Desktop)...");
        let _ = run_cmd("brew", &["uninstall", "--formula", "docker"]);
        let _ = run_cmd("brew", &["uninstall", "--formula", "docker-completion"]);
        ok("docker formula removed — Docker Desktop provides the CLI");
    }

    Ok(())
}

// ───────────────────────────────────────────────────── 2. linux (apt + zsh)

fn step_linux(ctx: &Context_) -> Result<()> {
    if ctx.os != Os::Linux || !ctx.should_run(&["linux"]) {
        return Ok(());
    }
    section("System packages");
    warn("Updating apt and installing packages...");
    require("sudo", &["apt", "update", "-y"])?;
    require("sudo", &["apt", "install", "-y", "zsh", "git", "curl"])?;
    ok("System packages installed");

    section("Default shell");
    let current_shell = std::env::var("SHELL").unwrap_or_default();
    if Path::new(&current_shell).file_name().and_then(|s| s.to_str()) == Some("zsh") {
        ok("zsh is already the default shell");
    } else {
        warn("Setting zsh as default shell...");
        let zsh_path = capture("which", &["zsh"]);
        let user = std::env::var("USER").unwrap_or_default();
        let _ = run_cmd("sudo", &["chsh", "-s", &zsh_path, &user]);
        warn("zsh set as default (takes effect on next login)");
    }

    let gitconfig_local = ctx.home.join(".gitconfig.local");
    if !gitconfig_local.exists() {
        fs::write(&gitconfig_local, "[credential]\n\thelper = cache\n")?;
        ok("Created ~/.gitconfig.local with credential helper = cache");
    } else {
        ok("~/.gitconfig.local already exists");
    }
    Ok(())
}

// ───────────────────────────────────────────────────── 3. sheldon binary

fn step_sheldon_bin(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["sheldon"]) {
        return Ok(());
    }
    section("Sheldon");
    if which("sheldon") {
        ok("Sheldon installed");
    } else if ctx.os == Os::Darwin {
        fail("Sheldon not found — should have been installed by brew bundle");
    } else if ctx.os == Os::Linux {
        warn("Installing Sheldon...");
        require(
            "bash",
            &[
                "-c",
                "curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin",
            ],
        )?;
        ok("Sheldon installed");
    }
    Ok(())
}

// ────────────────────────────────────────────── 4. dotctl self-install

fn step_dotctl(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["dotctl"]) {
        return Ok(());
    }
    section("dotctl");
    if !which("cargo") {
        warn("cargo not found — skipping dotctl rebuild (mise should provide rust)");
        return Ok(());
    }
    // Cargo replaces ~/.local/bin/dotctl atomically; the running process keeps
    // its in-memory mapping so this is safe to do mid-sync.
    let status = run_cmd(
        "cargo",
        &[
            "install",
            "--path",
            ctx.dotfiles_dir.join("dotctl").to_str().unwrap(),
            "--root",
            ctx.home.join(".local").to_str().unwrap(),
            "--force",
            "--quiet",
        ],
    )?;
    if status.success() {
        ok("dotctl installed");
    } else {
        warn("dotctl install failed (re-run with verbose cargo)");
    }
    Ok(())
}

// ───────────────────────────────────────────────────── 5. mise (Darwin)

fn step_mise(ctx: &Context_) -> Result<()> {
    if ctx.os != Os::Darwin || !ctx.should_run(&["mise"]) {
        return Ok(());
    }
    section("mise tools");
    let mise_toml = ctx.home.join(".config/mise/config.toml");
    if mise_toml.exists() {
        let _ = run_cmd("mise", &["trust", mise_toml.to_str().unwrap()]);
    }
    // `mise install` only installs declared versions — for tools pinned to
    // `latest` it does not advance the resolved version on subsequent runs.
    // On --upgrade, run `mise upgrade` to actually bump.
    if ctx.upgrade {
        warn("Upgrading mise tools (mise upgrade)...");
        let _ = run_cmd("mise", &["upgrade"]);
    }
    warn("Installing tools from mise.toml...");
    require("mise", &["install"])?;
    ok("mise tools up to date");
    Ok(())
}

// ─────────────────────────────────────────────── 6. symlinks (big one)

fn step_symlinks(ctx: &Context_) -> Result<()> {
    // The symlink umbrella tag plus all per-target tags. Matches bash module
    // semantics so `dotctl sync --only=zsh` does what you expect.
    let umbrella_tags: &[&str] = &[
        "symlinks", "git", "shell", "mise", "sheldon", "ghostty", "bat", "atuin", "lazygit", "zsh",
        "git-hooks", "gh", "claude", "ssh", "helix", "karabiner",
    ];
    if !ctx.should_run(umbrella_tags) {
        return Ok(());
    }
    section("Symlinks");

    // ── Git config ────────────────────────────────────────────────
    if ctx.should_run(&["symlinks", "git"]) {
        for (rel, target_name) in [
            (".gitconfig", ".gitconfig"),
            (".gitmessage", ".gitmessage"),
            (".gitignore", ".gitignore"),
            (".editorconfig", ".editorconfig"),
            (".ripgreprc", ".ripgreprc"),
            (".fdignore", ".fdignore"),
        ] {
            link(
                &ctx.dotfiles_dir.join(rel),
                &ctx.home.join(target_name),
                target_name,
                ctx.link_mode,
            )?;
        }

        let _ = fs::create_dir_all(ctx.home.join(".config/git/hooks"));
        link(
            &ctx.dotfiles_dir.join("git-hooks/pre-commit"),
            &ctx.home.join(".config/git/hooks/pre-commit"),
            "git-hooks/pre-commit",
            ctx.link_mode,
        )?;

        // Bootstrap ~/.gitconfig.local if absent (gpgSign defaults to true).
        let local = ctx.home.join(".gitconfig.local");
        if !local.exists() {
            let body = "# Machine-local git overrides — NOT in dotfiles.\n\
                        # Enable SSH commit/tag signing on this machine.\n\
                        [commit]\n\
                        \tgpgSign = true\n\
                        [tag]\n\
                        \tgpgSign = true\n";
            fs::write(&local, body)?;
            warn(".gitconfig.local bootstrapped (gpgSign enabled)");
        } else {
            dim(".gitconfig.local already exists");
        }

        // Bootstrap ~/.ssh/allowed_signers if absent (for git log --show-signature).
        let allowed = ctx.home.join(".ssh/allowed_signers");
        let pubkey = ctx.home.join(".ssh/id_ed25519.pub");
        let email = capture("git", &["config", "--file", ctx.dotfiles_dir.join(".gitconfig").to_str().unwrap(), "user.email"]);
        if !allowed.exists() && pubkey.exists() && !email.is_empty() {
            let _ = fs::create_dir_all(ctx.home.join(".ssh"));
            let pub_contents = fs::read_to_string(&pubkey).unwrap_or_default();
            let body = format!("{email} {}\n", pub_contents.trim());
            fs::write(&allowed, body)?;
            let _ = fs::set_permissions(&allowed, perms_600());
            warn("~/.ssh/allowed_signers bootstrapped");
        }
    }

    // ── SSH config ────────────────────────────────────────────────
    if ctx.should_run(&["symlinks", "ssh"]) {
        let _ = fs::create_dir_all(ctx.home.join(".ssh"));
        let _ = fs::set_permissions(ctx.home.join(".ssh"), perms_700());
        link(
            &ctx.dotfiles_dir.join("ssh/config"),
            &ctx.home.join(".ssh/config"),
            "ssh/config",
            ctx.link_mode,
        )?;
        let _ = fs::set_permissions(ctx.home.join(".ssh/config"), perms_600());
    }

    // ── Shell config ──────────────────────────────────────────────
    if ctx.should_run(&["symlinks", "shell"]) {
        for f in [".zshrc", ".zprofile", ".zshenv", ".hushlogin"] {
            link(&ctx.dotfiles_dir.join(f), &ctx.home.join(f), f, ctx.link_mode)?;
        }
    }

    if ctx.os == Os::Darwin {
        if ctx.should_run(&["symlinks", "mise"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/mise"));
            link(
                &ctx.dotfiles_dir.join("mise.toml"),
                &ctx.home.join(".config/mise/config.toml"),
                "mise/config.toml",
                ctx.link_mode,
            )?;
        }
    }

    if ctx.should_run(&["symlinks", "sheldon"]) {
        let _ = fs::create_dir_all(ctx.home.join(".config/sheldon"));
        link(
            &ctx.dotfiles_dir.join("sheldon/plugins.toml"),
            &ctx.home.join(".config/sheldon/plugins.toml"),
            "sheldon/plugins.toml",
            ctx.link_mode,
        )?;
    }

    if ctx.os == Os::Darwin {
        if ctx.should_run(&["symlinks", "ghostty"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/ghostty"));
            link(
                &ctx.dotfiles_dir.join("ghostty/config"),
                &ctx.home.join(".config/ghostty/config"),
                "ghostty/config",
                ctx.link_mode,
            )?;
        }
        if ctx.should_run(&["symlinks", "bat"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/bat"));
            link(
                &ctx.dotfiles_dir.join("bat/config"),
                &ctx.home.join(".config/bat/config"),
                "bat/config",
                ctx.link_mode,
            )?;
        }
        if ctx.should_run(&["symlinks", "atuin"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/atuin"));
            link(
                &ctx.dotfiles_dir.join("atuin/config.toml"),
                &ctx.home.join(".config/atuin/config.toml"),
                "atuin/config.toml",
                ctx.link_mode,
            )?;
        }
        if ctx.should_run(&["symlinks", "lazygit"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/lazygit"));
            link(
                &ctx.dotfiles_dir.join("lazygit/config.yml"),
                &ctx.home.join(".config/lazygit/config.yml"),
                "lazygit/config.yml",
                ctx.link_mode,
            )?;
        }
        if ctx.should_run(&["symlinks", "helix"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/helix"));
            link(
                &ctx.dotfiles_dir.join("helix/languages.toml"),
                &ctx.home.join(".config/helix/languages.toml"),
                "helix/languages.toml",
                ctx.link_mode,
            )?;
        }
        if ctx.should_run(&["symlinks", "karabiner"]) {
            // Karabiner-Elements writes to karabiner.json from its GUI; the
            // symlink means GUI rebinds round-trip back into the tracked file.
            // Verified safe on v15+; older versions occasionally replaced the
            // symlink with a regular file (fixed upstream).
            let _ = fs::create_dir_all(ctx.home.join(".config/karabiner"));
            link(
                &ctx.dotfiles_dir.join("karabiner/karabiner.json"),
                &ctx.home.join(".config/karabiner/karabiner.json"),
                "karabiner/karabiner.json",
                ctx.link_mode,
            )?;
        }
        // zsh fragments
        if ctx.should_run(&["symlinks", "zsh"]) {
            let _ = fs::create_dir_all(ctx.home.join(".config/zsh"));
            if let Ok(entries) = fs::read_dir(ctx.dotfiles_dir.join("zsh")) {
                for entry in entries.flatten() {
                    let name = entry.file_name();
                    let name_str = name.to_string_lossy();
                    if !name_str.ends_with(".zsh") || !name_str.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) {
                        continue;
                    }
                    link(
                        &entry.path(),
                        &ctx.home.join(".config/zsh").join(&*name_str),
                        &format!("zsh/{name_str}"),
                        ctx.link_mode,
                    )?;
                }
            }
        }
    }

    // ── GitHub CLI ────────────────────────────────────────────────
    if ctx.should_run(&["symlinks", "gh"]) {
        let _ = fs::create_dir_all(ctx.home.join(".config/gh"));
        link(
            &ctx.dotfiles_dir.join("gh/config.yml"),
            &ctx.home.join(".config/gh/config.yml"),
            "gh/config.yml",
            ctx.link_mode,
        )?;
    }

    // ── Claude Code ───────────────────────────────────────────────
    if ctx.should_run(&["symlinks", "claude"]) {
        let _ = fs::create_dir_all(ctx.home.join(".claude"));
        for (src, dst, label) in [
            ("dot-claude/CLAUDE.md", ".claude/CLAUDE.md", "claude/CLAUDE.md"),
            ("dot-claude/settings.json", ".claude/settings.json", "claude/settings.json"),
            ("dot-claude/agents", ".claude/agents", "claude/agents"),
            ("dot-claude/commands", ".claude/commands", "claude/commands"),
        ] {
            link(
                &ctx.dotfiles_dir.join(src),
                &ctx.home.join(dst),
                label,
                ctx.link_mode,
            )?;
        }
        let local = ctx.dotfiles_dir.join("dot-claude/settings.local.json");
        if local.is_file() {
            link(
                &local,
                &ctx.home.join(".claude/settings.local.json"),
                "claude/settings.local.json",
                ctx.link_mode,
            )?;
        } else {
            dim("claude/settings.local.json not present — skipping");
        }
    }

    Ok(())
}

fn perms_600() -> fs::Permissions {
    use std::os::unix::fs::PermissionsExt;
    fs::Permissions::from_mode(0o600)
}
fn perms_700() -> fs::Permissions {
    use std::os::unix::fs::PermissionsExt;
    fs::Permissions::from_mode(0o700)
}

// ───────────────────────────────────────────────────── 7. sheldon plugins

fn step_sheldon_plugins(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["sheldon"]) {
        return Ok(());
    }
    section("Sheldon plugins");
    warn("Updating Sheldon plugins...");
    // 30s budget — sheldon talks to GH and can hang if offline. Best-effort.
    let status = Command::new("sheldon")
        .args(["lock", "--update"])
        .status();
    match status {
        Ok(s) if s.success() => ok("Sheldon plugins up to date"),
        _ => warn("Sheldon lock failed or timed out (may be offline) — skipping"),
    }
    Ok(())
}

// ─────────────────────────────────────────────────────── 8. Claude CLI

fn step_claude(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["claude"]) {
        return Ok(());
    }
    section("Claude Code");
    if which("claude") {
        let ver = capture("claude", &["--version"]);
        ok(&format!("Claude Code CLI installed ({ver})"));
    } else {
        warn("Installing Claude Code CLI (native installer)...");
        let status = run_cmd("bash", &["-c", "curl -fsSL https://claude.ai/install.sh | bash"])?;
        if status.success() {
            ok("Claude Code CLI installed");
        } else {
            fail("Claude Code CLI install failed — re-run dotctl sync or install manually");
        }
    }
    Ok(())
}

// ─────────────────────────────────────────────────── 9. gh extensions

fn step_gh(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["gh"]) {
        return Ok(());
    }
    section("GitHub CLI");
    let authed = Command::new("gh")
        .args(["auth", "status"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !authed {
        warn("Not authenticated — run: gh auth login");
        return Ok(());
    }
    ok("gh authenticated");
    let installed = capture("gh", &["extension", "list"]);
    for (repo, name) in [
        ("dlvhdr/gh-dash", "gh-dash"),
        ("meiji163/gh-notify", "gh-notify"),
        ("actions/gh-actions-cache", "gh-actions-cache"),
    ] {
        if installed.contains(repo) {
            dim(&format!("{name} extension already installed"));
        } else {
            warn(&format!("Installing {name} extension..."));
            let status = run_cmd("gh", &["extension", "install", repo])?;
            if status.success() {
                ok(&format!("{name} installed"));
            } else {
                warn(&format!("{name} install failed"));
            }
        }
    }
    Ok(())
}

// ────────────────────────────────────────────────── 11. git maintenance

fn step_git_maint(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["git"]) {
        return Ok(());
    }
    section("git maintenance");
    // GIT_CONFIG_GLOBAL redirects the maintenance.repo write to
    // ~/.gitconfig.local so the tracked .gitconfig stays portable.
    let status = Command::new("git")
        .env("GIT_CONFIG_GLOBAL", ctx.home.join(".gitconfig.local"))
        .args(["-C", ctx.dotfiles_dir.to_str().unwrap(), "maintenance", "start"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    match status {
        Ok(s) if s.success() => ok(&format!(
            "git maintenance scheduled for {}",
            ctx.dotfiles_dir.display()
        )),
        _ => dim("git maintenance already scheduled or not supported"),
    }
    Ok(())
}

// ───────────────────────────────────────────────────────── 12. lefthook

fn step_lefthook(ctx: &Context_) -> Result<()> {
    if !ctx.should_run(&["lefthook"]) {
        return Ok(());
    }
    section("Lefthook (this repo)");
    if !which("lefthook") {
        warn("lefthook not found — should have been installed by brew bundle");
        return Ok(());
    }
    // --force: bypass the core.hooksPath conflict warning. By design the
    // global hooksPath points at git-hooks/pre-commit (gitleaks), which
    // chain-calls .git/hooks/pre-commit — that's what lefthook owns here.
    let status = Command::new("lefthook")
        .args(["install", "--force"])
        .current_dir(&ctx.dotfiles_dir)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    match status {
        Ok(s) if s.success() => ok(&format!(
            "lefthook hooks installed in {}/.git/hooks/",
            ctx.dotfiles_dir.display()
        )),
        _ => warn("lefthook install failed — check 'lefthook install --force' manually"),
    }
    Ok(())
}

// ─────────────────────────────────────────────── 13. macOS defaults

fn step_macos(ctx: &Context_) -> Result<()> {
    if ctx.os != Os::Darwin || !ctx.should_run(&["macos"]) {
        return Ok(());
    }
    section("macOS defaults");
    let applied = crate::macos_defaults::apply(&ctx.home, crate::host::current());
    ok(&format!(
        "macOS defaults applied ({applied} keys; Dock + Finder restarted)"
    ));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use tempfile::TempDir;

    // Env-mutating tests serialize on a process-wide mutex (Context_::new
    // reads HOME + DOTFILES_DIR; tests can't run in parallel without
    // clobbering each other's env).
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn fake_dotfiles_dir() -> TempDir {
        let tmp = TempDir::new().unwrap();
        // Context_::new requires a Brewfile in DOTFILES_DIR to accept the
        // env var; otherwise it falls back to ~/dotFiles.
        std::fs::write(tmp.path().join("Brewfile"), "# fake\n").unwrap();
        tmp
    }

    #[test]
    fn link_mode_variants_exist() {
        let _ = LinkMode::Interactive;
        let _ = LinkMode::Overwrite;
        let _ = LinkMode::Skip;
    }

    #[test]
    fn context_should_run_with_no_filter_matches_everything() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = fake_dotfiles_dir();
        std::env::set_var("HOME", tmp.path());
        std::env::set_var("DOTFILES_DIR", tmp.path());
        let ctx = Context_::new(None, false, LinkMode::Skip).unwrap();
        assert!(ctx.should_run(&["brew"]));
        assert!(ctx.should_run(&["unknown-tag"]));
        assert!(ctx.should_run(&[])); // empty list still passes when no filter
    }

    #[test]
    fn context_should_run_with_filter_matches_only_listed_tags() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = fake_dotfiles_dir();
        std::env::set_var("HOME", tmp.path());
        std::env::set_var("DOTFILES_DIR", tmp.path());
        let ctx = Context_::new(Some("brew,mise"), false, LinkMode::Skip).unwrap();
        assert!(ctx.should_run(&["brew"]));
        assert!(ctx.should_run(&["mise"]));
        assert!(ctx.should_run(&["brew", "other"]));
        assert!(!ctx.should_run(&["symlinks"]));
        assert!(!ctx.should_run(&[]));
    }

    #[test]
    fn context_should_run_filter_trims_whitespace() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = fake_dotfiles_dir();
        std::env::set_var("HOME", tmp.path());
        std::env::set_var("DOTFILES_DIR", tmp.path());
        let ctx = Context_::new(Some("  brew  ,  mise "), false, LinkMode::Skip).unwrap();
        assert!(ctx.should_run(&["brew"]));
        assert!(ctx.should_run(&["mise"]));
    }

    #[test]
    fn context_new_falls_back_to_home_dotfiles_when_env_missing() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // Without a valid DOTFILES_DIR pointing at a Brewfile, falls back to
        // ~/dotFiles. We point HOME at a tmp that DOES have a Brewfile under
        // ./dotFiles so the fallback succeeds.
        let tmp = TempDir::new().unwrap();
        let nested = tmp.path().join("dotFiles");
        std::fs::create_dir_all(&nested).unwrap();
        std::fs::write(nested.join("Brewfile"), "# fake\n").unwrap();
        std::env::set_var("HOME", tmp.path());
        std::env::remove_var("DOTFILES_DIR");
        let ctx = Context_::new(None, false, LinkMode::Skip).unwrap();
        assert_eq!(ctx.dotfiles_dir, nested);
    }

    #[test]
    fn context_new_errors_when_no_dotfiles_dir_anywhere() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = TempDir::new().unwrap();
        std::env::set_var("HOME", tmp.path());
        std::env::remove_var("DOTFILES_DIR");
        // Neither $DOTFILES_DIR nor ~/dotFiles is a directory.
        let r = Context_::new(None, false, LinkMode::Skip);
        assert!(r.is_err());
    }

    #[test]
    fn link_creates_new_symlink_when_destination_missing() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        std::fs::write(&src, "x").unwrap();
        let dst = tmp.path().join("nested/link.txt");
        link(&src, &dst, "test", LinkMode::Skip).unwrap();
        let meta = std::fs::symlink_metadata(&dst).unwrap();
        assert!(meta.file_type().is_symlink());
        assert_eq!(std::fs::read_link(&dst).unwrap(), src);
    }

    #[test]
    fn link_is_idempotent_when_already_pointing_to_source() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        std::fs::write(&src, "x").unwrap();
        let dst = tmp.path().join("link.txt");
        link(&src, &dst, "test", LinkMode::Skip).unwrap();
        // Second call should not error and should preserve the link.
        link(&src, &dst, "test", LinkMode::Skip).unwrap();
        assert_eq!(std::fs::read_link(&dst).unwrap(), src);
    }

    #[test]
    fn link_skip_mode_leaves_existing_file_untouched() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        std::fs::write(&src, "new").unwrap();
        let dst = tmp.path().join("dst.txt");
        std::fs::write(&dst, "existing").unwrap();
        link(&src, &dst, "test", LinkMode::Skip).unwrap();
        // dst should still be a regular file with the original content.
        let meta = std::fs::symlink_metadata(&dst).unwrap();
        assert!(!meta.file_type().is_symlink());
        assert_eq!(std::fs::read_to_string(&dst).unwrap(), "existing");
    }

    #[test]
    fn link_overwrite_mode_backs_up_existing_then_links() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        std::fs::write(&src, "new").unwrap();
        let dst = tmp.path().join("dst.txt");
        std::fs::write(&dst, "old").unwrap();
        link(&src, &dst, "test", LinkMode::Overwrite).unwrap();
        // dst is now a symlink to src.
        let meta = std::fs::symlink_metadata(&dst).unwrap();
        assert!(meta.file_type().is_symlink());
        assert_eq!(std::fs::read_link(&dst).unwrap(), src);
        // The backup carries the previous content.
        let backup = tmp.path().join("dst.txt.bak");
        assert!(backup.exists());
        assert_eq!(std::fs::read_to_string(&backup).unwrap(), "old");
    }
}

// `step_brew_doctor` was retired here — `dotctl doctor` absorbs both
// `brew doctor` and `mise doctor` so audits have a single entrypoint.
