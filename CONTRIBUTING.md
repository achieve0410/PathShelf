# Contributing

PathShelf is a local-first macOS utility. Keep changes narrow, dependency-free, and aligned with the offline and low-idle-work product boundary.

By participating, you agree to `CODE_OF_CONDUCT.md`. Project decisions and
maintainer responsibilities are documented in `GOVERNANCE.md`.

## Before You Start

1. Search existing issues and `ROADMAP.md`.
2. Use the bug or feature issue form for work that changes behavior.
3. Confirm the proposal fits the supported macOS, offline, file-safety, and
   low-idle-work boundaries.
4. Keep security reports private under `SECURITY.md`.

Small fixes may proceed directly through a pull request when their behavior and
verification are unambiguous. Material product, permission, dependency,
network, or distribution changes require an accepted design issue first.

## Development

Build on an Apple Silicon Mac running macOS 15 or later:

```sh
brew install ripgrep
swift build --arch arm64
```

Behavior changes require a failing test at the affected contract seam before
the implementation. Refactors must first characterize the observable behavior
they preserve. Documentation-only changes use review and rendered/read evidence
instead of tests that pin prose.

## Required Checks

```sh
bash BuildSupport/branding-audit.sh
swift build --arch arm64
bash BuildSupport/test.sh
bash BuildSupport/build-app.sh
bash BuildSupport/smoke-launch.sh
bash BuildSupport/performance-audit.sh
bash BuildSupport/release-audit.sh
bash BuildSupport/idle-audit.sh ci
bash BuildSupport/oss-readiness-audit.sh
```

Run hardware-sensitive performance and long idle audits sequentially on the
target Mac when preparing a release. Pull requests should name the exact
commands run and include the observable result.

## Pull Requests

- Keep each pull request focused on one outcome.
- Link the issue or explain why no issue is required.
- Describe failing-first and green evidence.
- Exercise the real app surface when behavior changes.
- Update `CHANGELOG.md` and public documentation when applicable.
- Do not weaken, skip, or suppress a failing check.

AI-assisted changes are welcome, but contributors remain responsible for
understanding every submitted line, removing confidential input, and providing
human-verified evidence. AI approval is not a substitute for maintainer review.

## Project Boundaries

Do not add third-party dependencies, app-owned network clients,
Accessibility/global event monitor paths, permanent delete behavior, or polling
loops without an accepted design review. Replacement must remain explicit and
file deletion must remain Trash-only.

## Local-Only Diagnostics

Use `OSLog` and `OSSignposter` only. Do not log full user file paths, secrets, credentials, or personal data.
