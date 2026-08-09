# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-07-30
- Primary product surfaces: floating file panel, settings window, menu bar item
- Evidence reviewed: `README.md`, `Sources/AppShell/FileBrowserPanelView.swift`, `Sources/AppShell/SettingsWindowController.swift`, contract-test behavior, and user feedback from 2026-07-29 through 2026-07-30

## Brand

- Personality: quiet, fast, local, predictable
- Trust signals: native macOS controls, explicit file actions and access grants, visible offline behavior
- Avoid: ambiguous pop-up labels, redundant instructional copy, subscription or cloud language, Finder imitation beyond useful platform conventions

## Product goals

- Goals: make frequent folders and local files reachable in one shortcut; make navigation and file actions self-explanatory; remain idle when hidden
- Non-goals: replace Finder, index the disk, permanently delete files, add online accounts
- Success signals: a first-time user can identify the current location, add a favorite, enter a folder, sort items, resize the panel, and discover file actions without documentation

## Personas and jobs

- Primary personas: keyboard-oriented macOS users who repeatedly access a small set of folders
- User jobs: open a panel from any app, navigate from Home or Favorites, inspect and open items, perform safe file operations
- Key contexts of use: short invocations over another app, laptop battery use, fully offline local work

## Information architecture

- Primary navigation: grouped and collapsible Favorites, direct folder activation, and clickable bottom path components for ancestor navigation
- Core routes/screens: floating file browser; native toolbar-based Settings
- Content hierarchy: labeled source-list Favorites sidebar with an always-present Default Group section and user-created groups; sortable file list with centered empty/error states; bottom Finder-style path bar with item count or error status; Settings divided into General, Shortcut, Browser, and Access toolbar panes

## Design principles

- Keep the file list visually primary; use conventional table-header sorting, contextual menus for actions, and a clickable native bottom path bar instead of a toolbar.
- Follow macOS conventions: double-click opens or enters, right-click reveals contextual actions, a visible divider resizes the Favorites sidebar, and the window frame is resizable.
- Open the panel in front when explicitly invoked, then keep it at the normal macOS window level so other application windows can naturally cover it.
- Keep persistent chrome concise: Favorites shows names without healthy-state labels or instructional copy; settings owns file-access guidance.
- Keep safe defaults: destructive actions require confirmation and replacement is never implicit.
- Tradeoffs: prefer native AppKit controls over custom visual styling; omit redundant Back/Up/Home controls because direct folder activation and Favorites cover the primary workflow.

## Visual language

- Color: macOS semantic system colors only; no fixed RGB palette or user-selectable theme
- Typography: macOS system font with standard control sizes
- Spacing/layout rhythm: 6–14 point control spacing; full-bleed panel content with 12 point path-bar insets; 16 point Settings section insets and 20–24 point pane margins
- Surface hierarchy: native sidebar material for Favorites, control background for the file list and grouped Settings controls, and window background for the Settings canvas and bottom path/status bar
- Shape/radius/elevation: 10 point Settings section radius with semantic separator borders; no custom shadow or decorative elevation
- Motion: none beyond standard macOS window behavior
- Imagery/iconography: SF Symbols or native file icons with text labels for unfamiliar actions; consistent scale by role (11 point group symbols, 14 point Settings symbols, 16 point Favorite icons, 18 point file icons)
- Appearance: follows the system Light/Dark appearance automatically; semantic colors and native materials remain compatible with Increase Contrast and Reduce Transparency

## Components

- Existing components to reuse: `NSPanel`, `NSSplitView`, `NSTableView`, `NSPopUpButton`, `NSMenu`, `NSWorkspace`
- New/changed components: labeled and adjustable-width grouped source-list Favorites with disclosure controls and configurable group icons, unavailable-state badges and native drag-and-drop reordering, clickable sortable headers, target-specific Favorites context menus, nested Open With menu, configurable detail columns, centered empty/error presentation, clickable `NSPathControl` bottom path bar, right-aligned item count, native four-pane Settings toolbar, grouped Settings action rows, resizable panel
- Variants and states: empty Default Group section, empty custom group, empty folder, unavailable location, selected file or folder, disabled action without a selection
- Token/component ownership: AppKit semantic values remain the source; a small shared metrics surface owns recurring spacing, radius, and icon sizes without introducing a custom theme layer

## Accessibility

- Target standard: native macOS accessibility semantics
- Keyboard/focus behavior: global shortcut opens the panel; Return opens or enters; Space previews; Delete requests Trash; Escape closes; Command-W closes the active panel or Settings window; Favorites can also be reordered with explicit Move Up/Down context actions
- Contrast/readability: system label colors and native selection states
- Screen-reader semantics: native path-control components and contextual menu item names describe location and action
- Reduced motion and sensory considerations: no custom animation

## Responsive behavior

- Supported breakpoints/devices: macOS 15+ Apple Silicon displays
- Layout adaptations: default panel is 1080×580 and user-resizable; Favorites stays within a bounded width, the file list retains a useful minimum, and the bottom item count remains pinned right
- Touch/hover differences: mouse and trackpad use native hover, double-click, divider drag, and context menu behavior

## Interaction states

- Loading: retain the panel structure while enumeration completes
- Empty: show a centered folder symbol and `This folder is empty`; keep the concise `Empty folder` status in the bottom bar
- Error: show a centered warning state with a concise title and the model error detail while retaining the error in the bottom status line
- Success: refresh the visible directory or Favorites immediately; path-component clicks navigate immediately; folder-access grants report their result in the Access pane
- Disabled: selection-dependent contextual actions are unavailable without a selected row
- Favorite organization: disclosure controls expand or collapse each group for the current app session; right-click creates, renames, changes the icon of, reorders, or deletes groups; dragging a Favorite onto a group moves it into that group, dragging between Favorites reorders it, and deleting a group returns its contents to Default Group
- Offline/slow network: local content works normally; provider-backed placeholders and mounted shares remain OS/provider responsibilities

## Content voice

- Tone: concise, literal, neutral
- Terminology: `Favorites`, `Add to Favorites`, `New Folder…`, `Open With…`, `Choose Accessible Folder…`, `Show This App in Finder`, `Full Disk Access`
- Microcopy rules: name the object and result; use ellipses when an action opens another choice or confirmation surface

## Implementation constraints

- Framework/styling system: AppKit-first, no third-party dependencies
- Design-token constraints: use AppKit semantic colors, fonts, spacing, and controls
- Performance constraints: no polling, background indexing, or hidden-panel work; sorting is in-memory over the visible directory
- Compatibility constraints: macOS 15+, arm64, offline-first
- Test/screenshot expectations: contract tests cover sort behavior, directory activation, and path-component navigation; smoke verifies the 1080×580 layout, labeled Favorites area, bottom path bar/action, right-aligned status, absence of panel navigation toolbar controls, native Settings toolbar/access guidance, and resizable panel

## Open questions

- [ ] Decide whether the selected sort order should persist across app relaunches after real-world use.
- [ ] Decide whether a later release needs a grid view in addition to the list view.
