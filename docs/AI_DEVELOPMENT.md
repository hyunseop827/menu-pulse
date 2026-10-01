# AI-assisted development

[한국어](AI_DEVELOPMENT.ko.md)

Menu Pulse is made by Hyunseop Kim with AI coding assistants, including Claude
Code. AI assistants write and revise the code, tests, scripts, and
documentation. The maintainer decides what to build, reviews and tries the
results, and publishes each release.

## Roles

- **Maintainer**: sets goals and priorities, makes product decisions, checks
  builds on a real Mac, and commits, pushes, and releases.
- **AI assistants**: implement changes, write tests and documentation, review
  the code, and prepare version numbers and release notes by following
  [`AGENTS.md`](../AGENTS.md). They do not commit, tag, push, or publish unless
  the maintainer asks.

## How changes are checked

- **Compiler and analyzer**: every warning is an error, and any Clang static
  analysis finding fails `make check`.
- **Tests**: `make check` runs four test executables and the benchmark tests.
  CI runs the same checks on pull requests and on pushes to `main`, before a
  release is published.
- **Reviews**: several independent AI reviewers examine the code from different
  angles, such as correctness, unused code, performance, and documentation. Other
  agents then try to refute each finding, and only confirmed issues are fixed.
- **Real hardware**: behavior that tests cannot cover is checked on a Mac, for
  example temperature readings against the raw sensor values, disk figures
  against Finder, an update and restart of a test copy, and README screenshots
  captured from the current build.

## Limitations

- AI-written code can be wrong. Reviews and tests reduce that risk but do not
  remove it.
- Temperature readings use private IOKit interfaces that may change between
  macOS versions.
- The app is ad-hoc signed and not notarized by Apple.

Please report problems on [GitHub Issues](https://github.com/hyunseop827/menu-pulse/issues).

## Working on Menu Pulse with an AI assistant

Start with [`AGENTS.md`](../AGENTS.md); `CLAUDE.md` imports it for Claude Code.
[`ARCHITECTURE.md`](ARCHITECTURE.md) describes how the app works.
