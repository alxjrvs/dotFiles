// hook: claude_statusline — check out a PINNED tag of the statusline repo beside the
// dotfiles repo and symlink its two scripts onto PATH. Input: with.repo, with.ref.
//
// Never a moving branch, never the upstream `install.sh`: `with.ref` names a tag, so bumping
// the widget is a commit here, and the two symlinks are made below by name rather than by
// handing the upstream code execution on every sync. Not a `mise` entry: mise's github/ubi
// backends install RELEASE ASSETS, and this repo publishes tags with no releases attached.

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
// Pinned. Bump deliberately, in a commit, after reading what changed.
const DEFAULT_REF = "v1.1.1";
// The two scripts install.sh used to symlink, named here so the hook never has to run it.
const LINKS: ReadonlyArray<readonly [string, string]> = [
  ["statusline.sh", "claude-statusline"],
  ["subagent-statusline.sh", "claude-subagent-statusline"],
];

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
  const ref = api.with.ref ?? DEFAULT_REF;
  const url = `https://${repo}.git`;
  if (api.dryRun) {
    api.note(
      `would check out ${url} at ${ref} → ${TARGET} and symlink 2 scripts`,
    );
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
  if (!existsSync(join(TARGET, ".git"))) {
    await $`git clone -q ${url} ${TARGET}`.nothrow().quiet();
    api.ok(`statusline cloned → ${TARGET}`);
  }
  // Fetch the tag by name and check out that object. Detached HEAD is the point:
  // this checkout is derived state, and nothing here should ever track a branch.
  await $`git -C ${TARGET} fetch -q --tags origin`.nothrow().quiet();
  const at =
    await $`git -C ${TARGET} rev-parse --verify -q ${`${ref}^{commit}`}`
      .nothrow()
      .quiet();
  if (at.exitCode !== 0) {
    api.warn(
      `statusline: ${repo} has no ref ${ref} — leaving the checkout alone`,
    );
    return;
  }
  await $`git -C ${TARGET} checkout -q --detach ${ref}`.nothrow().quiet();
  api.ok(`statusline at ${ref}`);

  // What install.sh did, by name, in a file that gets reviewed.
  const bin = join(api.env.HOME ?? "", ".local", "bin");
  await $`mkdir -p ${bin}`.nothrow().quiet();
  for (const [src, name] of LINKS) {
    const from = join(TARGET, src);
    if (!existsSync(from)) {
      api.warn(`statusline: ${repo}@${ref} has no ${src}`);
      continue;
    }
    await $`chmod +x ${from}`.nothrow().quiet();
    await $`ln -sfn ${from} ${join(bin, name)}`.nothrow().quiet();
  }
  api.ok("statusline linked onto PATH");
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
