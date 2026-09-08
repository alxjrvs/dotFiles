// git-signing — resolve the ONE signing value that has to be discovered, and record it.
//
// Everything constant about signing (`commit.gpgSign`, `tag.gpgSign`, `gpg.format`,
// `gpg.ssh.program`, `gpg.ssh.allowedSignersFile`) is in the tracked `home/dot_gitconfig`,
// where it is reviewable and identical on every machine. What is genuinely dynamic is
// `user.signingkey`: looked up BY NAME from the 1Password agent, so a rotated key converges
// without anyone editing a file. The public key is also appended to ~/.ssh/allowed_signers so
// `git log --show-signature` verifies locally.
//
// Run by chezmoi (home/run_after_91-git-signing.sh.tmpl) on every apply, or by hand:
//   bun run scripts/git-signing.ts [KEY_NAME]      (default GitHubSSH)
// Exit 0 always: a machine without 1Password is reported, never failed — signing is then
// simply not converged, and `verify.sh` says nothing about it because nothing can.

import {
  appendFileSync,
  chmodSync,
  existsSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { $ } from "bun";

const HOME = process.env.HOME ?? "";
const REPO = join(import.meta.dir, "..");
const PROG = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
const SOCK = join(
  HOME,
  "Library",
  "Group Containers",
  "2BUA8C4S2C.com.1password",
  "t",
  "agent.sock",
);
const name = process.argv[2] ?? "GitHubSSH";

const log = (s: string) => console.log(`git-signing: ${s}`);

// "<type> <data>" of the named signing key from the 1Password agent ("" if unavailable).
async function pubkey(): Promise<string> {
  if (!existsSync(SOCK)) return "";
  const out = await $`ssh-add -L`
    .env({ ...process.env, SSH_AUTH_SOCK: SOCK })
    .nothrow()
    .quiet()
    .text()
    .catch(() => "");
  const line = out.split("\n").find((l) => l.trimEnd().endsWith(` ${name}`));
  if (!line) return "";
  const [type, data] = line.split(/\s+/);
  return type && data ? `${type} ${data}` : "";
}

if (!existsSync(PROG)) {
  log("op-ssh-sign not found (install 1Password) — skipping");
  process.exit(0);
}
const pub = await pubkey();
if (!pub) {
  log(
    `1Password agent not offering "${name}" (running? SSH agent enabled?) — skipping`,
  );
  process.exit(0);
}

// Machine-local git overrides: sign with the 1Password key via op-ssh-sign.
const cfg = join(HOME, ".gitconfig.local");
if (!existsSync(cfg))
  writeFileSync(
    cfg,
    "# Machine-local git overrides — NOT in dotfiles. Written by scripts/git-signing.ts.\n",
  );
const want = `key::${pub}`;
const cur = (
  await $`git config --file ${cfg} user.signingkey`
    .nothrow()
    .quiet()
    .text()
    .catch(() => "")
).trim();
if (cur !== want) {
  await $`git config --file ${cfg} user.signingkey ${want}`.nothrow().quiet();
  log(`signingkey set to the 1Password "${name}" key`);
}

// allowed_signers (append-only) so `git log --show-signature` verifies locally.
const allowed = join(HOME, ".ssh", "allowed_signers");
const email = (
  await $`git config --file ${join(REPO, "home", "dot_gitconfig")} user.email`
    .nothrow()
    .quiet()
    .text()
    .catch(() => "")
).trim();
if (email) {
  const line = `${email} ${pub}`;
  const have =
    existsSync(allowed) &&
    readFileSync(allowed, "utf8").split("\n").includes(line);
  if (!have) {
    appendFileSync(allowed, `${line}\n`);
    log("allowed_signers updated");
  }
  chmodSync(allowed, 0o600);
}
log("signing converged (op-ssh-sign)");
