# Changelog

All notable user-facing and maintainer-facing changes are recorded here.
PathShelf follows [Semantic Versioning](https://semver.org/) for public
releases.

## Unreleased

## [0.2.1] - 2026-08-12

### Fixed

- Kept visible directory contents stable during filesystem-event refreshes,
  preventing repeated `Loading…` flashes in noisy or file-provider-backed
  folders while continuing to reflect later changes at the same path.

## [0.2.0] - 2026-08-12

### Added

- Native configuration export and import for app settings, Favorite groups,
  and saved locations, including explicit replacement confirmation and
  recovery for unavailable imported Favorites.
- Current-folder filename filtering with native search, clear, loading, and
  no-results states.
- A visible `Add Favorite…` action, Return-key Favorite activation, and
  explicit VoiceOver semantics for Favorite groups and availability.
- A consent-based `Send Beta Feedback…` menu action, structured public issue
  form, and fixed two-week validation protocol without telemetry or automatic
  upload.
- A fail-closed Developer ID and notarization candidate workflow plus
  deterministic local-QA app packaging and checksum audits.

### Changed

- Expanded contract, AppKit smoke, performance, idle, network, packaging, and
  open-source readiness verification.
- Updated product and market-readiness documentation with evidence-constrained
  scoring and explicit external validation thresholds.

### Fixed

- Prevented path-bar navigation from escaping the active Favorite permission
  boundary or mutating browser state after a rejected destination.

## [0.1.0] - 2026-08-10

### Added

- Public governance, support, security-reporting, and maintainer workflow
  documentation.
- GitHub issue and pull-request contribution templates.
- A repeatable open-source readiness audit.

### Changed

- CI policy now requires explicit least privilege, bounded execution, and
  immutable action references.

### Removed

- Internal planning and agent-session artifacts from the public source surface.

[0.2.1]: https://github.com/achieve0410/PathShelf/releases/tag/v0.2.1
[0.2.0]: https://github.com/achieve0410/PathShelf/releases/tag/v0.2.0
[0.1.0]: https://github.com/achieve0410/PathShelf/releases/tag/v0.1.0
