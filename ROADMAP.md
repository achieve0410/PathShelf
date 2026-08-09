# Roadmap

This roadmap communicates priorities; it is not a promise of dates or specific
features. Accepted work still requires an issue, review, and passing checks.

## Current: v0.1.0 source release

- Publish `v0.1.0` as a source-only GitHub release with generated source
  archives, build instructions, release notes, and green CI.
- Keep the public repository, private vulnerability reporting, dependency
  monitoring, and protected-main checks operational.
- Treat the AppShell decomposition required for v0.1.0 as complete. Further
  splitting of composition-root types is optional maintenance work.

## Next: maintenance and adoption

- Triage real user feedback and document recurring support cases.
- Improve accessibility verification with VoiceOver and high-contrast checks.
- Decide whether to distribute a Developer ID-signed and notarized binary.
- Before any binary performance or battery claims, validate the performance,
  network, and ten-minute idle audits on target hardware.
- Add release provenance and a documented reproducible packaging path.
- Evaluate sort-order persistence after observing real-world use.

## Later: evidence-driven product work

- Consider list filtering for large visible directories.
- Consider navigation history and multi-selection only after their interaction
  and file-safety contracts are specified.
- Revisit a grid presentation only if user evidence justifies the added surface.

## Non-goals

Finder replacement, permanent deletion, telemetry, accounts, background disk
indexing, and app-owned cloud or network services are not roadmap targets.
