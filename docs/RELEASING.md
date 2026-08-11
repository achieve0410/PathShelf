# Releasing

PathShelf supports source-only and binary release types. A release is complete
only when its type, source, tag, checks, and known limitations can be verified
publicly. Binary-only requirements do not apply when no binary is distributed.

## Prerequisites

- A clean revision reviewed through the repository's pull-request process.
- Apple Silicon hardware running macOS 15 or later.
- `ripgrep` available for static policy and readiness audits.
- A public repository remote controlled by the releasing maintainer.
- For a binary release only, an approved Developer ID identity and notarization
  credentials. Do not store those credentials in the repository.

## Source-only release gates

The protected `macos` CI job on the tagged revision is the public gate for a
source-only release. Reproduce that workflow locally, in order, with:

```sh
bash BuildSupport/branding-audit.sh
swift build --arch arm64
bash BuildSupport/test.sh
bash BuildSupport/build-app.sh
bash BuildSupport/smoke-launch.sh
bash BuildSupport/release-audit.sh
bash BuildSupport/idle-audit.sh ci
bash BuildSupport/oss-readiness-audit.sh
```

GitHub-generated source archives are the only artifacts for a source-only
release. Do not upload the ad-hoc local app bundle.

## Binary release gates

Before a binary release or binary performance and battery claims, also run:

```sh
bash BuildSupport/performance-audit.sh
bash BuildSupport/idle-audit.sh release
```

These results are hardware-sensitive evidence. Record the target Mac model,
macOS version, thresholds, and output in the release notes. The performance
gate enforces shell-launch-to-interactive latency and macOS physical footprint.
It also records app-main latency and resident size so app work and
shared-mapping costs remain visible separately.

## Version and changelog

1. Choose a Semantic Versioning version.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `BuildSupport/Info.plist`.
3. Move relevant entries from `CHANGELOG.md`'s Unreleased section to the
   versioned release section.
4. Re-run the gates for the selected release type after version metadata
   changes.

## Binary signing and artifacts

`BuildSupport/build-app.sh` creates an ad-hoc signed local bundle. That artifact
is suitable for local testing, not a claim of Developer ID signing or
notarization.

To exercise archive creation locally without creating a distributable binary:

```sh
PATHSHELF_ALLOW_ADHOC_QA=1 bash BuildSupport/package-release.sh
bash BuildSupport/release-package-audit.sh
```

The package metadata is `distribution=local-qa-only`. Do not upload that
archive or present it as a release.

Before distributing a binary:

1. Sign the bundle with an approved Developer ID Application identity.
2. Submit it to Apple's notarization service and staple the result.
3. Verify the final artifact with `codesign`, `spctl`, and a clean-machine
   launch.
4. Archive the app and generate a SHA-256 checksum.

Never publish an ad-hoc artifact as though it were notarized.

Authorized maintainers can run the manual `Binary Release Candidate` workflow
after configuring the repository's Developer ID certificate and App Store
Connect notarization secrets. The workflow fails before building if any secret
is absent or the selected ref is not `main`, uses hardened-runtime Developer ID
signing, waits for notarization, staples and assesses the app, and uploads only
the notarized zip, checksum, and package metadata as a workflow artifact. An
always-run step removes imported signing and notarization files. The workflow
does not create a tag or GitHub Release.

## Source-only publication

After the source-only gates pass:

1. Confirm protected `main` CI is green on the exact release revision.
2. Create the version tag and a non-draft, non-prerelease GitHub Release.
3. Upload no custom assets; use only GitHub-generated source archives.
4. Link the changelog and include clone, build, app-bundle, test, and smoke
   commands.
5. State that binary signing, notarization, installation, Gatekeeper checks,
   and binary checksums are not applicable because no binary is distributed.

## Binary publication

Create a binary release only after both the source and binary gates pass.
Attach the notarized checksummed artifact, include installation and Gatekeeper
expectations, and state which hardware-sensitive audits were run.

Repository publication, tag creation, GitHub releases, signing, and notarization
are external actions and require an authorized maintainer.
