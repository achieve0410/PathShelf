# Maintainer Workflows

This document defines evidence the project maintains continuously, including
the workflows for which maintainer-assistance programs may be used.

## Issue triage

Maintainers classify reports as reproducible bugs, security reports, support
requests, feature proposals, or out-of-scope requests. Private paths and
bookmark data must be removed before public discussion. A bug is ready for work
when it has a minimal reproduction and an observable expected result.

## Pull-request review

Review covers:

1. File-operation safety and permission boundaries.
2. Main-thread, cancellation, observer, and teardown behavior.
3. Offline and no-polling constraints.
4. Tests that can fail for the named regression.
5. Build, smoke, audit, documentation, and changelog impact.

AI-assisted contributions are welcome, but the contributor remains responsible
for understanding the change, disclosing material generated content when useful
to reviewers, and providing reproducible evidence. Maintainers do not merge a
change solely because an AI review or test suite reports success.

## Release maintenance

Releases follow `docs/RELEASING.md`. Maintainers record exact gate results,
hardware-sensitive measurements, signing state, known limitations, and
checksums. Failed gates remain visible until corrected; they are not waived.

## Security maintenance

Candidate security issues are handled privately under `SECURITY.md`. Useful
review targets include:

- Path traversal and symbolic-link boundary errors.
- Time-of-check/time-of-use races in file operations.
- Bookmark scope lifetime and permission transitions.
- Unsafe overwrite, replacement, and Trash behavior.
- Stale callbacks after panel teardown.
- Unexpected network symbols, sockets, or entitlements.

## Responsible use of automated development tools

Automated development tools may assist with issue classification, reproduction
plans, test design, pull-request review, security analysis, release-note
drafting, and audit-result summaries. Maintainers must:

- Provide only repository data they are authorized to share.
- Exclude credentials, bookmark data, private paths, and confidential reports
  unless the approved security workflow explicitly permits processing them.
- Verify generated code and security findings against the real app.
- Keep repository permissions least-privileged.
- Record human-reviewed evidence for merged changes and releases.

Tool access, sponsorship, or automated security analysis does not constitute
project adoption, maintainer endorsement, or security certification.

## Current evidence and external evidence

The repository directly provides build, contract, smoke, performance, release,
network, idle, and open-source readiness checks. Public usage, repository
ownership, maintainer permissions, release tags, signed artifacts, downloads,
and external contributors can only be claimed after they exist on the public
hosting surface.
