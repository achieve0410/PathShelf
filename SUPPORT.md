# Support

PathShelf is maintained as a focused open-source macOS utility.

## Before opening an issue

1. Confirm the Mac is Apple Silicon and runs macOS 15 or later.
2. Build the latest revision with `swift build --arch arm64`.
3. Run `bash BuildSupport/test.sh`.
4. Search existing issues for the same behavior.

## Bug reports

Use the GitHub bug report form and include:

- macOS version and Mac model.
- The smallest reproducible sequence.
- Expected and actual behavior.
- Whether the location is local, iCloud-backed, removable, or a mounted share.
- Sanitized diagnostics that do not contain private file paths.

Do not attach bookmark data, credentials, private paths, or personal files.

## Feature proposals

Use the feature request form. Explain the user problem and how the proposal
fits the offline-first, dependency-free, and low-idle-work boundaries.

## Security reports

Do not open a public issue for a vulnerability. Follow `SECURITY.md`.

## Scope

Supported work is described in `README.md` and `ROADMAP.md`. Intel Macs,
macOS 14 and earlier, permanent deletion, background indexing, accounts,
telemetry, and app-owned network services are currently out of scope.
