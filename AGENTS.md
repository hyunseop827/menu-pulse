# Menu Pulse

Menu Pulse is a small native Objective-C/AppKit app for Apple Silicon Macs.
Keep the app lightweight and keep `Scripts/` limited to the user-facing benchmark.

## Preparing changes for the user's commit

CI treats changes to `Sources/`, `Packaging/`, or `Makefile` as app build input
changes. Prepare their version and release notes before handing them back to the
user:

- Fetch the current remote tags (`git fetch --tags origin`, without force) before
  choosing a version; tags created by CI may not exist locally yet.
  If the current version is already tagged,
  choose the next semantic version: patch for fixes, minor for new features.
  If a newer version is already being prepared locally, keep that version and
  update its notes rather than incrementing it again on each conversation turn.
- Set both `CFBundleShortVersionString` and `CFBundleVersion` in
  `Packaging/Info.plist` to the same version.
- Update `.github/release-notes.md`. Its first line must be `# vX.Y.Z`, matching
  the app version. Write 3–5 concise bullets about the actual user-visible changes
  since the previous release. The user may edit this text before committing.
- Run `make check` for app changes. For workflow changes, also check the workflow
  syntax and test release decisions without publishing to the real repository.
- Documentation-only changes do not need a version bump or a new release.

The user normally commits and pushes. CI validates a `main` push, then creates
the prepared version tag and publishes the DMG and notes. Do not make commits,
tags, pushes, or GitHub releases unless the user asks. Never move an existing
release tag to another commit.

Keep release procedure details out of the public READMEs. Release notes belong
on GitHub Releases; the file above holds the upcoming release's editable text.
