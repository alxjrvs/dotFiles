// hook: claude_statusline — clone the statusline repo beside the dotfiles repo and
// run its installer. Input: with.repo (git url). Ported from claude_statusline.sh.
import { $ } from "bun";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";

interface Api {
  with: Record<string, string>;
  env: Record<string, string | undefined>;
  dryRun: boolean;
  ok(s: string): void;
  warn(s: string): void;
  note(s: string): void;
}

// hooks/<name>.ts lives in <dotfiles>/hooks, so the repo is one dir up; the
// statusline checkout sits beside the dotfiles repo (was $BOTU_CONFIG/..).
const TARGET = join(import.meta.dir, "..", "..", "claude-statusline");

export async function apply(api: Api): Promise<void> {
  const repo = api.with.repo ?? "github.com/alxjrvs/claude-statusline";
  const url = `https://${repo}.git`;
  if (api.dryRun) {
    api.note(`would clone ${url} → ${TARGET} and run install.sh`);
    return;
  }
  if (existsSync(join(TARGET, ".git"))) {
    await $`git -C ${TARGET} pull --ff-only -q`.nothrow().quiet();
    api.ok("statusline updated");
  } else {
    await $`git clone -q ${url} ${TARGET}`.nothrow().quiet();
    api.ok(`statusline cloned → ${TARGET}`);
  }
  if (existsSync(join(TARGET, "install.sh"))) {
    await $`./install.sh`.cwd(TARGET).nothrow().quiet();
    api.ok("statusline installed");
  }
}

export function verify(api: Api): void {
  const bin = join(api.env.HOME ?? "", ".local", "bin", "claude-statusline");
  if (existsSync(bin) && (statSync(bin).mode & 0o111) !== 0) api.ok("statusline on PATH");
  else api.warn("statusline missing — botu apply --only=claude_statusline");
}

// fix is re-apply (botu falls back to apply when fix is absent), so nothing to add.
