# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-11
- Primary product surfaces: floating file panel, settings window, menu bar item
- Evidence reviewed: `README.md`, `docs/PRODUCT_AUDIT_AND_IMPROVEMENT_PLAN.md`, `Sources/AppShell/FileBrowserPanelView.swift`, `Sources/AppShell/SettingsWindowController.swift`, contract-test behavior, native smoke captures, and user feedback from 2026-07-29 through 2026-08-11

## Brand

- Personality: quiet, fast, local, predictable
- Trust signals: native macOS controls, explicit file actions and access grants, visible offline behavior
- Avoid: ambiguous pop-up labels, redundant instructional copy, subscription or cloud language, Finder imitation beyond useful platform conventions

## Product goals

- Goals: make frequent folders and local files reachable in one shortcut; let users narrow the current folder without disk indexing; make navigation and file actions self-explanatory; remain idle when hidden
- Non-goals: replace Finder, index the disk, permanently delete files, add online accounts
- Success signals: a first-time user can identify the current location, add a favorite, enter a folder, filter it by filename, clear the filter, sort items, resize the panel, discover file actions, and intentionally reach the public beta feedback form without documentation

## Personas and jobs

- Primary personas: keyboard-oriented macOS users who repeatedly access a small set of folders
- User jobs: open a panel from any app, navigate from Home or Favorites, narrow the current folder by filename, inspect and open items, perform safe file operations
- Key contexts of use: short invocations over another app, laptop battery use, fully offline local work

## Information architecture

- Primary navigation: grouped and collapsible Favorites, direct folder activation, and clickable bottom path components for ancestor navigation
- Core routes/screens: floating file browser; native toolbar-based Settings; app and status menus with one user-initiated beta feedback command
- Content hierarchy: labeled source-list Favorites sidebar with an always-present Default Group section and user-created groups; a compact native search row immediately above the sortable file list; centered loading/empty/no-results/error states; bottom Finder-style path bar with result/item count or error status; Settings divided into General, Shortcut, Browser, and Access toolbar panes

## Design principles

- Keep the file list visually primary; use a compact `NSSearchField`, conventional table-header sorting, contextual menus for actions, and a clickable native bottom path bar instead of a navigation toolbar.
- Follow macOS conventions: double-click opens or enters, right-click reveals contextual actions, a visible divider resizes the Favorites sidebar, and the window frame is resizable.
- Open the panel in front when explicitly invoked, then keep it at the normal macOS window level so other application windows can naturally cover it.
- Keep persistent chrome concise: the search row occupies one native control height, Favorites shows names without healthy-state labels or instructional copy, and Settings owns file-access guidance.
- Keep safe defaults: destructive actions require confirmation and replacement is never implicit.
- Keep validation consent-based: `Send Beta Feedback…` opens the public GitHub issue form only after a direct menu action; PathShelf records and uploads no usage, paths, filenames, credentials, or personal data.
- Tradeoffs: prefer native AppKit controls over custom visual styling; omit redundant Back/Up/Home controls because direct folder activation and Favorites cover the primary workflow.

## Visual language

- Color: macOS semantic system colors only; no fixed RGB palette or user-selectable theme
- Typography: macOS system font with standard control sizes
- Spacing/layout rhythm: 6–14 point control spacing; full-bleed panel content with 12 point search/path-bar insets; 16 point Settings section insets and 20–24 point pane margins
- Surface hierarchy: native sidebar material for Favorites, control background for the file list and grouped Settings controls, and window background for the Settings canvas and bottom path/status bar
- Shape/radius/elevation: 10 point Settings section radius with semantic separator borders; no custom shadow or decorative elevation
- Motion: none beyond standard macOS window behavior
- Imagery/iconography: SF Symbols or native file icons with text labels for unfamiliar actions; consistent scale by role (11 point group symbols, 14 point Settings symbols, 16 point Favorite icons, 18 point file icons)
- Appearance: follows the system Light/Dark appearance automatically; semantic colors and native materials remain compatible with Increase Contrast and Reduce Transparency

## Components

- Existing components to reuse: `NSPanel`, `NSSplitView`, `NSTableView`, `NSPopUpButton`, `NSMenu`, `NSWorkspace`
- New/changed components: labeled and adjustable-width grouped source-list Favorites with disclosure controls and configurable group icons, unavailable-state badges and native drag-and-drop reordering, compact native `NSSearchField` with clear affordance, clickable sortable headers, target-specific Favorites context menus, nested Open With menu, configurable detail columns, centered loading/empty/no-results/error presentation, clickable `NSPathControl` bottom path bar, right-aligned item/result count, native four-pane Settings toolbar, grouped Settings action rows, resizable panel
- Variants and states: empty Default Group section, empty custom group, empty folder, active filename filter, no matching items, unavailable location, selected file or folder, disabled action without a selection
- Token/component ownership: AppKit semantic values remain the source; a small shared metrics surface owns recurring spacing, radius, and icon sizes without introducing a custom theme layer

## Accessibility

- Target standard: native macOS accessibility semantics
- Keyboard/focus behavior: global shortcut opens the panel; Command-F focuses the search field; Return opens or enters; Space previews; Delete requests Trash; Escape clears a non-empty filter before closing the panel; Command-W closes the active panel or Settings window; Favorites can also be reordered with explicit Move Up/Down context actions; Shortcut modifiers use a two-column native grid so every label remains visible
- Contrast/readability: system label colors and native selection states
- Screen-reader semantics: the search field announces `Filter current folder`; result status announces matching and total counts; the no-results state names the active query; native path-control components and contextual menu item names describe location and action
- Reduced motion and sensory considerations: no custom animation

## Responsive behavior

- Supported breakpoints/devices: macOS 15+ Apple Silicon displays
- Layout adaptations: default panel is 1080×580 and user-resizable; Favorites stays within a bounded width; the search field remains usable at the 800×460 minimum; the Name column retains priority; and the bottom result/item count remains pinned right
- Touch/hover differences: mouse and trackpad use native hover, double-click, divider drag, and context menu behavior

## Interaction states

- Loading: retain the panel structure while user-initiated navigation
  enumerates; filesystem-event refreshes keep the current content visible,
  update it in place, and must not restart the watcher or flash `Loading…`
- Empty: show a centered folder symbol and `This folder is empty`; keep the concise `Empty folder` status in the bottom bar
- Filtering: filter the already loaded current directory by locale-aware, case-insensitive filename matching; retain the active query across refreshes of the same directory and clear it when navigation changes location
- No results: show a centered magnifying-glass symbol, `No matching items`, and a concise query-specific detail; keep `0 of n items` in the bottom bar
- Error: show a centered warning state with a concise title and the model error detail while retaining the error in the bottom status line
- Success: update filter results as the user types; clearing the query restores the full current-directory snapshot immediately; refresh the visible directory or Favorites immediately; path-component clicks inside the active Home/configured/Favorite navigation root navigate immediately; folder-access grants report their result in the Access pane
- Navigation boundary: a path-component target outside the active navigation root is ignored before URL, history, filter, visible items, or security-scope state changes
- Disabled: selection-dependent contextual actions are unavailable without a selected row
- Favorite organization: disclosure controls expand or collapse each group for the current app session; right-click creates, renames, changes the icon of, reorders, or deletes groups; dragging a Favorite onto a group moves it into that group, dragging between Favorites reorders it, and deleting a group returns its contents to Default Group
- Favorite discovery: keep a native `Add Favorite…` action visible below the Favorites list even when no locations exist; opening it presents the existing folder chooser without adding toolbar clutter
- Favorite keyboard/accessibility: Return opens the selected Favorite; group disclosure exposes its group name and expanded/collapsed state; Favorite rows expose their display name and access availability to VoiceOver
- Beta feedback: place one native `Send Beta Feedback…` item next to Settings in both the app and status menus; dispatch the exact public HTTPS issue-form URL to the default browser after activation and add no primary-panel chrome
- Offline/slow network: local content works normally; provider-backed placeholders and mounted shares remain OS/provider responsibilities

## Content voice

- Tone: concise, literal, neutral
- Terminology: `Favorites`, `Add to Favorites`, `New Folder…`, `Open With…`, `Choose Accessible Folder…`, `Send Beta Feedback…`, `Show This App in Finder`, `Full Disk Access`
- Microcopy rules: name the object and result; use ellipses when an action opens another choice or confirmation surface

## Implementation constraints

- Framework/styling system: AppKit-first, no third-party dependencies
- Design-token constraints: use AppKit semantic colors, fonts, spacing, and controls
- Performance constraints: no polling, background indexing, hidden-panel work, telemetry, accounts, automatic feedback upload, or app-owned network service; sorting and filtering are in-memory over the loaded current directory
- Compatibility constraints: macOS 15+, arm64, offline-first
- Test/screenshot expectations: contract tests cover sort behavior, filename filter/clear restoration, directory activation, positive path-component navigation, and rejection outside an active Favorite root; beta audit parses the machine-consumed feedback schema; smoke invokes the production beta-feedback `NSMenu` action at an intercepted browser-adapter boundary and verifies its HTTPS host/path/template while retaining all existing 1080×580 panel, Favorite, search, path-boundary, Settings, and resize checks

## Accepted design debt

- The first filter increment matches filenames only; content, tag, fuzzy, and full-disk search remain intentionally out of scope.
- Unified native close teardown and Settings dirty/discard state remain prioritized follow-up accessibility/usability work documented in `docs/PRODUCT_AUDIT_AND_IMPROVEMENT_PLAN.md`.
- External WindowServer screenshots are unavailable in the current QA session; fresh evidence is captured from the same running AppKit views through the smoke-only native capture hook.

## Open questions

- [ ] Decide whether the selected sort order should persist across app relaunches after real-world use.
- [ ] Decide whether a later release needs a grid view in addition to the list view.
