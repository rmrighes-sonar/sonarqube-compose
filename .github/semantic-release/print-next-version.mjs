// Prints `version=X.Y.Z` for $GITHUB_OUTPUT -- the version this commit
// would become per .releaserc.json's rules, computed against commits since
// the last `vX.Y.Z` tag, WITHOUT creating a tag or GitHub Release (dryRun).
// `ci: false` bypasses semantic-release's own branch/CI-context checks so
// this also works as a preview on PR/feature-branch runs, not just on
// `main` -- the real, tag-creating run only ever happens in the `release`
// job, gated to `push` events on `main`.
//
// Falls back to the latest existing tag (stripped of its `v` prefix) if
// semantic-release determines no release is warranted for the current
// HEAD, so sonar.projectVersion always has *something* meaningful rather
// than an empty string.
import { execSync } from "node:child_process";
import semanticRelease from "semantic-release";

const result = await semanticRelease({ dryRun: true, ci: false });

if (result) {
  console.log(`version=${result.nextRelease.version}`);
} else {
  const lastTag = execSync(
    "git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0",
  )
    .toString()
    .trim()
    .replace(/^v/, "");
  console.log(`version=${lastTag}`);
}
