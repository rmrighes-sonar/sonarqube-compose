// Writes `version=X.Y.Z` directly to $GITHUB_OUTPUT -- the version this
// commit would become per .releaserc.json's rules, computed against
// commits since the last `vX.Y.Z` tag, WITHOUT creating a tag or GitHub
// Release (dryRun).
//
// Only actually invokes semantic-release on `push` events: its
// branch-matching check (unrelated to, and not bypassable via, the
// dryRun/ci options) requires HEAD to genuinely be on a branch listed in
// .releaserc.json's `branches`. A `push` to `main` really is checked out
// on refs/heads/main, so this works there without any tricks. A
// `pull_request` run, however, is always checked out at a detached
// synthetic merge ref (refs/pull/N/merge) -- semantic-release reads
// GitHub's own GITHUB_REF env var directly for this (confirmed by testing
// -- neither `ci: false` nor pointing a local branch literally named
// `main` at HEAD changes that), so it always refuses to compute anything
// there, dry run or not.
//
// That's fine to just accept rather than work around: SonarQube's
// PR-analysis mode defines "new code" as "diff vs target branch," not by
// version, so an approximate version on PR runs doesn't affect
// correctness -- only the `main` branch's analysis history (which this
// *does* get exactly right) feeds a "New Code = Previous version" boundary.
// PR runs fall back to the latest existing tag instead.
import { execSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import semanticRelease from "semantic-release";

const lastTag = () =>
  execSync("git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0")
    .toString()
    .trim()
    .replace(/^v/, "");

let version;
if (process.env.GITHUB_EVENT_NAME === "push") {
  const result = await semanticRelease({ dryRun: true });
  version = result ? result.nextRelease.version : lastTag();
} else {
  version = lastTag();
}

appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}\n`);
console.log(`Computed next version: ${version}`);
