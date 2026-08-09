# PathShelf

PathShelf is an offline-first macOS 15+ Apple Silicon utility for fast access to saved folders from a lightweight floating panel.

The app is intentionally local-only: no telemetry, no accounts, no update checks, and no app-initiated network client. iCloud placeholder downloads and network shares remain OS/provider behavior, not app-owned traffic.

## Project Status

PathShelf v0.1.0 is the first public source release. GitHub provides the source
archives, while users build and run the app locally; no prebuilt app binary is
included.

The project is designed as a reference-quality native utility: file operations
default to safe outcomes, hidden-panel work is explicitly torn down, and offline
claims are backed by source, binary, and runtime checks rather than telemetry.

## MVP Features

- Global shortcut through Carbon `RegisterEventHotKey`, without Accessibility, CGEventTap, or global event monitoring.
- Floating AppKit `NSPanel` with cursor-adjacent or active-display top-center placement.
- Resizable 1080×580 default panel with grouped Favorites, clickable Finder-style bottom path bar, and right-aligned item count.
- Clickable Name and optional detail headers for sorting the visible directory.
- Settings for hidden files, optional Modified/Kind/Size/Created/Availability columns, the default startup folder, persistent folder access, and Full Disk Access guidance.
- Double-click folder navigation plus native file and Favorite context menus.
- User-created Favorite groups with configurable icons, drag-and-drop grouping, and reordering; deleting a group preserves its entries in Default Group.
- Nested Open With menu for Finder and installed VS Code, iTerm2, Terminal, and Chrome applications.
- First-run settings guidance, reopen handling, and a persistent folder icon in the menu bar.
- Settings window from the app menu or menu bar status item.
- Settings for panel placement, shortcut key/modifiers, and launch at login.
- Launch at login via `SMAppService.mainApp`, with user-visible status: enabled, requires approval, not registered, or app service not found.
- Saved locations, home navigation, basic panel file browsing, safe operation contracts, Quick Look/thumbnail contracts, and lifecycle teardown diagnostics.

## Platform

- macOS 15 or later
- Apple Silicon (`arm64`)
- Swift Package Manager
- [ripgrep](https://github.com/BurntSushi/ripgrep) for local tests and audits
- MIT license

## Build

From a fresh checkout of the release:

```sh
git clone --branch v0.1.0 --depth 1 https://github.com/achieve0410/PathShelf.git
cd PathShelf
brew install ripgrep
swift build --arch arm64
```

To create the local app bundle:

```sh
bash BuildSupport/build-app.sh
open .build/PathShelf.app
```

The generated bundle is ad-hoc signed for local validation. It is not a
Developer ID-signed or notarized public artifact. See `docs/RELEASING.md` before
distributing a binary.

## Test

```sh
bash BuildSupport/test.sh
```

The test suite uses dependency-free executable contract runners because Command Line Tools-only environments may not provide Apple's XCTest or Swift Testing modules.

Current runners cover settings, shortcut atomicity, launch-at-login rollback behavior, file access, file operations, panel behavior, event-driven refresh, teardown counters, and forbidden static patterns.

## Run Smoke

```sh
bash BuildSupport/smoke-launch.sh
```

The smoke harness injects isolated settings/bookmark/fixture paths, launches the app, verifies hotkey registration, fallback surfaces, saved placement, panel focus, fixture enumeration, teardown counters, and emits machine-readable performance metrics.

## Audits

```sh
bash BuildSupport/performance-audit.sh
bash BuildSupport/release-audit.sh
bash BuildSupport/idle-audit.sh ci
bash BuildSupport/oss-readiness-audit.sh
```

For the longer battery-oriented idle check:

```sh
bash BuildSupport/idle-audit.sh release
```

`release` mode defaults to 60 seconds stabilization plus 600 seconds measurement. CI mode is intentionally short and only proves the harness and local invariants.

Audit scripts rebuild and run the shared `.build/PathShelf.app` bundle. Run them sequentially; the scripts also take a simple local lock to avoid concurrent rebuild/runtime races in the shared bundle path.

`performance-audit.sh` is a reference-device check, not a CI gate. It creates a local `.build/perf-fixture-*` directory with exactly 1,000 visible files and 10 saved locations before launch. `cold_ms` is measured from the shell launch timestamp to the first selectable row after directory enumeration and table selection. `warm_p95_ms` is the p95 of 20 panel invocations, each measured until the first selectable row is ready.

The audit also records `app_cold_ms` from app main to that same row. The memory
limit is enforced against macOS physical footprint; resident size remains
recorded because it includes shared mappings and is not app-owned memory.
Before the measured process, an untimed linker preflight exits at the first line
of app main. This normalizes shared-framework residency without initializing
the app; `cold_ms` still covers a new process from its shell launch timestamp.

`idle-audit.sh` uses `ProcessMetricsProbe`, which reads `proc_pid_rusage` for process CPU time, physical footprint, and disk read/write byte deltas. It does not use major page faults as an I/O proxy.

`network-audit.sh` combines static source and symbol checks with short runtime `lsof` sampling. When available, `nettop -L` CSV output is sampled and `bytes_in + bytes_out` is summed as `runtime_socket_bytes`. `dns_api_symbols=0` means no DNS/network client symbols were found by static scan; it is not a packet capture claim. Root-only tools such as `fs_usage` or `dtruss` are not run by these scripts.

`oss-readiness-audit.sh` verifies the tracked public source surface, required
maintainer documents and contribution templates, actionable private security
reporting, and baseline GitHub Actions hardening.

## Offline And Network Semantics

- Local files work offline.
- Locally hydrated iCloud files work offline.
- iCloud placeholders may require macOS/provider download when opened.
- Mounted network shares require the underlying network mount.
- The app binary and runtime audits reject app-owned network clients, network entitlements, and app-originated sockets in the local fixture.

## Known Limits

- Full Finder replacement is not the goal.
- v0.1.0 is source-only; no Developer ID-signed or notarized app binary is
  provided.
- Hardware battery validation and the 10-minute release idle audit must be run
  on target hardware before making binary performance or battery claims.
- The default CI workflow does not gate hardware-sensitive performance numbers or the 10-minute idle mode.
- App Store distribution, telemetry, backend sync, permanent delete, Accessibility permission, and third-party dependencies are out of scope.

## Project Documents

- Contributing: `CONTRIBUTING.md`
- Governance: `GOVERNANCE.md`
- Maintainers: `MAINTAINERS.md`
- Support: `SUPPORT.md`
- Security: `SECURITY.md`
- Roadmap: `ROADMAP.md`
- Changelog: `CHANGELOG.md`
- Release process: `docs/RELEASING.md`
- Maintainer workflows: `docs/MAINTAINER_WORKFLOWS.md`

## License

MIT. See `LICENSE`.
