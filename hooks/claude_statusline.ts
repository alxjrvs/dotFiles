// hook: claude_statusline — clone the statusline repo beside the dotfiles repo and
// run its installer. Input: with.repo (git url). Ported from claude_statusline.sh.

import { existsSync, readFileSync, statSync } from "node:fs";
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

// hooks/<name>.ts lives in <dotfiles>/hooks, so the repo is one dir up; the
// statusline checkout sits beside the dotfiles repo (was $BOOM_CONFIG/..).
const TARGET = join(import.meta.dir, "..", "..", "claude-statusline");
const DEFAULT_REPO = "github.com/TheGnarCo/claude-statusline";

// True when TARGET is a checkout of some *other* remote than `url`. Reads
// .git/config rather than shelling out, so verify() can stay sync.
function pointsElsewhere(url: string): boolean {
  if (!existsSync(join(TARGET, ".git"))) return false;
  try {
    return !readFileSync(join(TARGET, ".git", "config"), "utf8").includes(url);
  } catch {
    return false;
  }
}

export async function sync(api: Api): Promise<void> {
  const repo = api.with.repo ?? DEFAULT_REPO;
  const url = `https://${repo}.git`;
  if (api.dryRun) {
    api.note(`would clone ${url} → ${TARGET} and run install.sh`);
    return;
  }
  // The boomfile declares the upstream, so honor a change to it. Re-clone
  // rather than re-point: this checkout is derived state (never edited in
  // place), and a re-seeded upstream shares no history with the old one — the
  // Gnar statusline was seeded from alxjrvs/claude-statusline rather than
  // forked, so `pull` across the switch dies on unrelated histories.
  if (pointsElsewhere(url)) {
    await $`rm -rf ${TARGET}`.nothrow().quiet();
    api.note(`upstream is now ${repo} — re-cloning`);
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
  if (existsSync(bin) && (statSync(bin).mode & 0o111) !== 0)
    api.ok("statusline on PATH");
  else api.warn("statusline missing — boom source --only=claude_statusline");

  // A machine that cloned before the upstream changed keeps pulling the old
  // remote forever, and the scripts on PATH look fine — so name that drift.
  const repo = api.with.repo ?? DEFAULT_REPO;
  if (pointsElsewhere(`https://${repo}.git`))
    api.warn(
      `statusline upstream is not ${repo} — boom source --only=claude_statusline`,
    );
}

// repair falls back to sync (boom uses sync when a hook has no repair), so nothing to add.
