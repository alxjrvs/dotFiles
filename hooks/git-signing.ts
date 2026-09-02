// hook: git-signing — resolve the ONE signing value that has to be discovered, and
// record it. Everything constant about signing (`commit.gpgSign`, `tag.gpgSign`,
// `gpg.format`, `gpg.ssh.program`, `gpg.ssh.allowedSignersFile`) is in the tracked
// `.gitconfig`, where it is reviewable and identical on every machine.
//
// What is left here is genuinely dynamic: `user.signingkey` is looked up BY NAME from
// the 1Password agent (with.key, default GitHubSSH), so a rotated key converges without
// anyone editing a file; and the public key is appended to ~/.ssh/allowed_signers so
// `git log --show-signature` verifies locally.
//
// Why the constants are not written here as well: `.gitconfig`'s `[gpg "ssh"]` comment.

import {
  appendFileSync,
  chmodSync,
  existsSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { $ } from "bun";

interface Api {
  with: Record<string, string>;
  env: Record<string, string | undefined>;
  dryRun: boolean;
  ok(s: string): void;
  warn(s: string): void;
  note(s: string): void;
}

const DOTFILES = join(import.meta.dir, ".."); // hooks/ → repo root (was $BOOM_CONFIG)
const PROG = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
const home = (api: Api): string => api.env.HOME ?? "";
const sock = (api: Api): string =>
  join(
    home(api),
    "Library",
    "Group Containers",
    "2BUA8C4S2C.com.1password",
    "t",
    "agent.sock",
  );

// "<type> <data>" of the named signing key from the 1Password agent ("" if unavailable).
async function pubkey(api: Api, name: string): Promise<string> {
  if (!existsSync(sock(api))) return "";
  const out = await $`ssh-add -L`
    .env({ ...api.env, SSH_AUTH_SOCK: sock(api) })
    .nothrow()
    .quiet()
    .text()
    .catch(() => "");
  const line = out.split("\n").find((l) => l.trimEnd().endsWith(` ${name}`));
  if (!line) return "";
  const [type, data] = line.split(/\s+/);
  return type && data ? `${type} ${data}` : "";
}

export async function sync(api: Api): Promise<void> {
  const name = api.with.key ?? "GitHubSSH";
  if (api.dryRun) {
    api.note(
      "would converge signing in ~/.gitconfig.local + ~/.ssh/allowed_signers",
    );
    return;
  }
  if (!existsSync(PROG)) {
    api.warn(
      "op-ssh-sign not found (install 1Password) — skipping signing setup",
    );
    return;
  }
  const pub = await pubkey(api, name);
  if (!pub) {
    api.warn(
      `1Password agent not offering "${name}" (running? SSH agent enabled?) — skipping`,
    );
    return;
  }

  // Machine-local git overrides: sign with the 1Password key via op-ssh-sign.
  const cfg = join(home(api), ".gitconfig.local");
  if (!existsSync(cfg))
    writeFileSync(
      cfg,
      "# Machine-local git overrides — NOT in dotfiles. Written by boom.\n",
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
    api.ok(`signingkey set to the 1Password "${name}" key`);
  }

  // allowed_signers (append-only) so `git log --show-signature` verifies locally.
  const allowed = join(home(api), ".ssh", "allowed_signers");
  const email = (
    await $`git config --file ${join(DOTFILES, ".gitconfig")} user.email`
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
      api.ok("allowed_signers updated");
    }
    chmodSync(allowed, 0o600);
  }
  api.ok("signing converged (op-ssh-sign)");
}

// Asserts the one value sync() writes. It used to read `commit.gpgSign` from the same file —
// a constant that moved into the tracked `.gitconfig` — so a machine first synced after that
// move warned forever, and the remedy it printed could not clear it.
export function verify(api: Api): void {
  const cfg = join(home(api), ".gitconfig.local");
  const r = Bun.spawnSync(["git", "config", "--file", cfg, "user.signingkey"], {
    stdout: "pipe",
    stderr: "ignore",
  });
  const key = new TextDecoder().decode(r.stdout).trim();
  if (r.exitCode === 0 && key.startsWith("key::")) {
    api.ok("signingkey set from the 1Password agent (~/.gitconfig.local)");
  } else {
    api.warn("signingkey not set — run: boom source --only=git-signing");
  }
}
