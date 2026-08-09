# Governance

PathShelf uses a maintainer-led model appropriate for a focused desktop
utility. The goal is transparent decisions without adding process that exceeds
the project's size.

## Roles

- **Contributors** submit issues, documentation, tests, or code.
- **Reviewers** are trusted contributors who regularly provide technically
  useful review.
- **Maintainers** have repository write access and may merge changes, manage
  releases, and handle private reports.
- **Repository administrators** manage permissions, security settings, and
  ownership changes.

Current role ownership is recorded in `MAINTAINERS.md`.

## Decisions

Routine changes are decided in pull requests after required checks pass.
Maintainers prefer the smallest change that preserves the documented
offline-first and low-idle-work boundary.

Material decisions should begin in a public issue before implementation:

- Changing the supported macOS or CPU baseline.
- Adding a dependency or app-initiated network path.
- Changing file deletion, replacement, or permission behavior.
- Adding Accessibility, Screen Recording, or Full Disk Access requirements.
- Changing signing, sandbox, or distribution strategy.

When maintainers disagree, they document the alternatives and rationale in the
issue. The repository administrator makes the final decision when consensus
cannot be reached.

## Becoming a maintainer

A contributor may be invited after sustained, high-quality participation that
demonstrates sound judgment around file safety, macOS lifecycle behavior,
review quality, and respectful collaboration. Access starts at the least
privileged level needed and is reviewed after periods of inactivity.

## Security and conduct

Security reports follow `SECURITY.md`; conduct reports follow
`CODE_OF_CONDUCT.md`. Maintainers must not use confidential reports for any
purpose beyond investigation, remediation, and coordinated disclosure.

## Governance changes

Governance changes use the normal pull-request process and require approval from
a repository administrator. A change that affects contributor rights or
reporting expectations must include a migration note in `CHANGELOG.md`.
