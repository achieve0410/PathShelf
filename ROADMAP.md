# Roadmap

This roadmap communicates priorities; it is not a promise of dates or specific
features. Accepted work still requires an issue, review, and passing checks.

## Now: first public release

- Finish the current AppShell source decomposition without behavior changes.
- Publish a clean public repository and enable private vulnerability reporting.
- Complete release signing and notarization decisions.
- Produce a verifiable `v0.1.0` release with checksums and release notes.
- Validate the full release, network, performance, and ten-minute idle audits on
  the target hardware.

## Next: maintenance and adoption

- Triage real user feedback and document recurring support cases.
- Improve accessibility verification with VoiceOver and high-contrast checks.
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
