// hook: git-signing — converge git commit/tag signing via 1Password op-ssh-sign.
// Writes machine-local ~/.gitconfig.local + appends ~/.ssh/allowed_signers, using the
// 1Password-agent key named by with.key (default GitHubSSH). gpgSign stays
// machine-local so a box without 1Password doesn't fail commits. Ported from
// git-signing.sh.
import { $ } from "bun";
import { appendFileSync, chmodSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

interface Api {
  with: Record<string, string>;
  env: Record<string, string | undefined>;
  dryRun: boolean;
  ok(s: string): void;
  warn(s: string): void;
  note(s: string): void;
}

const DOTFILES = join(import.meta.dir, ".."); // hooks/ → repo root (was $BOTU_CONFIG)
const PROG = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
const home = (api: Api): string => api.env.HOME ?? "";
const sock = (api: Api): string =>
  join(home(api), "Library", "Group Containers", "2BUA8C4S2C.com.1password", "t", "agent.sock");

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

export async function apply(api: Api): Promise<void> {
  const name = api.with.key ?? "GitHubSSH";
  if (api.dryRun) {
    api.note("would converge signing in ~/.gitconfig.local + ~/.ssh/allowed_signers");
    return;
  }
  if (!existsSync(PROG)) {
    api.warn("op-ssh-sign not found (install 1Password) — skipping signing setup");
    return;
  }
  const pub = await pubkey(api, name);
  if (!pub) {
    api.warn(`1Password agent not offering "${name}" (running? SSH agent enabled?) — skipping`);
    return;
  }

  // Machine-local git overrides: sign with the 1Password key via op-ssh-sign.
  const cfg = join(home(api), ".gitconfig.local");
  if (!existsSync(cfg)) writeFileSync(cfg, "# Machine-local git overrides — NOT in dotfiles. Written by botu.\n");
  await $`git config --file ${cfg} commit.gpgSign true`.nothrow().quiet();
  await $`git config --file ${cfg} tag.gpgSign true`.nothrow().quiet();
  await $`git config --file ${cfg} gpg.ssh.program ${PROG}`.nothrow().quiet();
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
    const have = existsSync(allowed) && readFileSync(allowed, "utf8").split("\n").includes(line);
    if (!have) {
      appendFileSync(allowed, `${line}\n`);
      api.ok("allowed_signers updated");
    }
    chmodSync(allowed, 0o600);
  }
  api.ok("signing converged (op-ssh-sign)");
}

export function verify(api: Api): void {
  const cfg = join(home(api), ".gitconfig.local");
  const r = Bun.spawnSync(["git", "config", "--file", cfg, "commit.gpgSign"], { stdout: "pipe", stderr: "ignore" });
  if (r.exitCode === 0 && new TextDecoder().decode(r.stdout).trim() === "true") {
    api.ok("commit signing enabled (~/.gitconfig.local)");
  } else {
    api.warn("signing not configured — run: botu apply --only=git-signing");
  }
}
