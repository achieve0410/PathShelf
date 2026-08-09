# Releasing

PathShelf has no public release yet. A release is complete only when its
source, tag, artifacts, checks, signing state, and known limitations can be
verified publicly.

## Prerequisites

- A clean revision reviewed through the repository's pull-request process.
- Apple Silicon hardware running macOS 15 or later.
- A public repository remote controlled by the releasing maintainer.
- For distributable binaries, an approved Developer ID identity and notarization
  credentials. Do not store those credentials in the repository.

## Local release gates

Run sequentially:

```sh
bash BuildSupport/branding-audit.sh
swift build --arch arm64
bash BuildSupport/test.sh
bash BuildSupport/build-app.sh
bash BuildSupport/smoke-launch.sh
bash BuildSupport/performance-audit.sh
bash BuildSupport/release-audit.sh
bash BuildSupport/idle-audit.sh release
bash BuildSupport/oss-readiness-audit.sh
```

The performance and long idle results are hardware-sensitive evidence. Record
the target Mac model, macOS version, thresholds, and output in the release
notes.

The performance gate enforces shell-launch-to-interactive latency and macOS
physical footprint. It also records app-main latency and resident size so app
work and shared-mapping costs remain visible separately. An untimed
linker-only process exits at app main before the measured process so shared
framework residency is consistent across reference-device runs.

## Version and changelog

1. Choose a Semantic Versioning version.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `BuildSupport/Info.plist`.
3. Move relevant entries from `CHANGELOG.md`'s Unreleased section to the
   versioned release section.
4. Re-run every release gate after version metadata changes.

## Signing and artifacts

`BuildSupport/build-app.sh` creates an ad-hoc signed local bundle. That artifact
is suitable for local testing, not a claim of Developer ID signing or
notarization.

Before distributing a binary:

1. Sign the bundle with an approved Developer ID Application identity.
2. Submit it to Apple's notarization service and staple the result.
3. Verify the final artifact with `codesign`, `spctl`, and a clean-machine
   launch.
4. Archive the app and generate a SHA-256 checksum.

Never publish an ad-hoc artifact as though it were notarized.

## Public release

Create the tag and GitHub release only after the gates pass. Attach the
checksummed artifact, include installation and Gatekeeper expectations, link the
changelog, and state which hardware-sensitive audits were run.

Repository publication, tag creation, GitHub releases, signing, and notarization
are external actions and require an authorized maintainer.
