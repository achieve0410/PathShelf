# Security Policy

## Supported Versions

Security fixes target the latest v0.1.x release and the latest revision on the
default branch for macOS 15+ on Apple Silicon.

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| Earlier revisions | No |

## Private Reporting

Do not publish suspected vulnerability details in an issue, pull request, or
discussion. Use
[GitHub private vulnerability reporting](../../security/advisories/new) to send
the report to repository maintainers.

Include:

- A concise impact statement.
- A minimal reproduction using sanitized paths and fixtures.
- Affected macOS and hardware versions.
- Any conditions required to cross a permission or file-safety boundary.
- A suggested remediation if one is known.

Do not submit credentials, security-scoped bookmark data, private file paths, or
personal files. If GitHub private vulnerability reporting is unavailable,
contact the repository owner through the private contact method on the owner's
GitHub profile and disclose only enough information to establish a secure
channel.

Maintainers aim to acknowledge a complete report within seven days and provide
a status update within fourteen days. These are response targets, not a bug
bounty or a promise of a specific remediation date.

## Security Boundary

- No telemetry.
- No app-initiated network client.
- No account system or backend.
- No Accessibility, Screen Recording, or Full Disk Access requirement.
- User-selected folders are persisted through sandbox-conscious bookmark contracts.
- Delete means Trash-only in the MVP.

High-value review areas include path and symbolic-link boundaries,
time-of-check/time-of-use races, bookmark scope lifetime, file replacement,
stale callbacks after teardown, and unexpected network symbols or entitlements.

## Coordinated Disclosure

Maintainers validate the report, prepare a regression proof, develop the
smallest fix, and coordinate disclosure with the reporter. Public disclosure
waits until a fix or documented mitigation is available unless users face an
active threat that requires earlier notice.

## Out of Scope

- Social engineering or physical access attacks.
- Vulnerabilities that require unsupported macOS or Intel hardware.
- Provider-owned iCloud or mounted-share network behavior outside the app.
- Automated testing that accesses systems or repositories without permission.

## Sensitive Data

Do not include API keys, tokens, private keys, customer data, credentials, cookies, or full private file paths in logs, issues, tests, or fixtures.
