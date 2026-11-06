---
name: release
description: Cut a Bagnon Cheapest release on the owner's machine. Drafts the player-facing notes from the commits and CHANGELOG, opens a release PR with the version bump, and after it merges makes the annotated v<version> tag on main whose message is the notes. Pushes the tag only after the owner says yes.
disable-model-invocation: true
---

# Release Bagnon Cheapest

The GitHub workflow publishes whatever the tag says. No AI runs there. This
skill is where the notes get written and checked, on the owner's machine,
with the owner approving each step that matters.

The pieces:

- The version lives only in `Bagnon_Cheapest/Bagnon_Cheapest.toc`, on its
  `## Version:` line.
- `CHANGELOG.md` keeps a `## <version>` section for every release. Changes
  pile up under `## Unreleased` between releases, added as they're made.
- The tag `v<version>` is **annotated**, and its message is the release
  notes. The workflow reads them with `scripts/release.py notes` and uses
  them for the GitHub release and CurseForge.
- `python scripts/release.py check v<version>` checks all of that. The
  workflow runs it first and stops if it fails.

Follow the steps in order. Stop and tell the owner if any check fails. Don't
work around it.

## 1. Check the starting point

```sh
git branch --show-current          # must be main
git status --short                 # must be empty
git fetch origin main --tags
git rev-parse HEAD origin/main     # must be the same commit
```

Then `python tests/run.py` must pass.

## 2. Gather what changed

```sh
LAST=$(git describe --tags --abbrev=0 2>/dev/null)   # empty before the first release
git log --oneline ${LAST:+$LAST..}HEAD
```

Start from the `## Unreleased` section of `CHANGELOG.md`. Then read the
commits, and the diff where a message is unclear, to find anything a player
would notice that the section missed. If the TOC's version has no tag yet
and the CHANGELOG already has its section, offer to release that version,
with that section plus anything under `## Unreleased` as the starting draft.

## 3. Pick the version with the owner

Suggest one and say why: a patch (`1.1.1`) for fixes only, a minor (`1.2.0`)
for new features. A suffix makes a pre-release: `-beta.1` or `-rc.1` is a
CurseForge **Beta**, `-alpha.1` an **Alpha**. Check the tag is free:

```sh
git rev-parse -q --verify "refs/tags/v<version>"   # must print nothing
git ls-remote --tags origin "v<version>"           # must print nothing
```

## 4. Draft the notes

Write them for players, not developers.

- Plain English, short sentences, Markdown. Bullets, with `### New` and
  `### Fixed` headings when there are both kinds.
- Only what a player can notice. Leave out refactors, tests, docs, CI and
  release tooling.
- Concise and to the point.
- Don't say something works in game unless the owner confirmed it.

Show the draft to the owner. Change it until they approve it. The approved
text is used as is in both the CHANGELOG and the tag.

## 5. Write the version and the changelog

Set `## Version: <version>` in `Bagnon_Cheapest/Bagnon_Cheapest.toc`. Keep
the file's encoding as it is (no byte-order mark).

In `CHANGELOG.md`, put the approved notes under `## <version>`, right below
an empty `## Unreleased`. Replace the `## <version>` section if it's already
there. Then:

```sh
python tests/run.py
python scripts/release.py package   # release/Bagnon_Cheapest-<version>.zip
```

## 6. Confirm in-game testing

Ask the owner whether they've tried this build in game. The owner tests in
game; you can't. Don't go on until they say yes.

## 7. Open the release PR

```sh
git checkout -b "release-v<version>"
git add Bagnon_Cheapest/Bagnon_Cheapest.toc CHANGELOG.md
git commit -m "Release v<version>"
git push -u origin "release-v<version>"
```

Write the approved notes to a file in your scratchpad (not in the repo).
Open a PR titled `Release v<version>` with the notes as its body:
`gh pr create --title "Release v<version>" --body-file <notes-file>`. Give
the owner the link and wait for them to merge it. Nothing is published by
the merge; only the tag publishes.

## 8. Tag main

Once the PR is merged:

```sh
git checkout main
git pull origin main
git log --oneline -3                 # the release PR must be the latest change
grep '^## Version' Bagnon_Cheapest/Bagnon_Cheapest.toc   # must say <version>
```

If something else was merged after the release PR, stop and ask the owner.
The tag would include it, and the notes wouldn't mention it.

```sh
git tag -a "v<version>" -F <notes-file> --cleanup=verbatim
```

`--cleanup=verbatim` matters. Without it, git treats every line starting
with `#` as a comment and drops it, so the `###` headings vanish.

Check the tag:

```sh
python scripts/release.py check "v<version>"
python scripts/release.py notes --tag "v<version>" --out <scratchpad>/check.md
diff <notes-file> <scratchpad>/check.md    # must print nothing
```

If anything is wrong, fix it, `git tag -d "v<version>"`, and tag again. The
tag is only local until step 9.

## 9. Push the tag, only when the owner says so

Show the owner the version, the commit the tag is on, and the notes. Ask:
"Push the tag?" Push only on a clear yes.

```sh
git push origin "v<version>"
```

Then tell the owner:

- **Actions → Release** is running: check, test, GitHub release, then
  CurseForge (skipped until its token and project id are set).
- Check the GitHub release page when it's done.
- After CurseForge moderation, install from the CurseForge app, `/reload`,
  and check the addon list shows the new version.

## After a push

Never move or delete a pushed tag unless the owner asks.

- **Notes need a fix:** edit the GitHub release, then run **Actions → Upload
  to CurseForge** with the tag (it reads the release's notes). Fix the
  `CHANGELOG.md` section in a normal PR.
- **The workflow failed before publishing** (for example the check): fix it
  in a PR, then release the next patch version. Re-using the same version is
  also fine, but only if the owner agrees to delete the pushed tag
  (`git push origin :refs/tags/v<version>`).
- **The workflow failed after the build** (GitHub or CurseForge was down):
  **Re-run failed jobs**, or **Actions → Release → Run workflow** with the
  tag.
