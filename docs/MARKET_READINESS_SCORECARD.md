# PathShelf Market Readiness Scorecard

Checked: 2026-08-12

## Decision

PathShelf has a credible product wedge, but it is not yet proven to have
sufficient market value.

- Baseline: **55/100**
- After market cycle 1: **57/100**
- Sufficient-market-value threshold: **70/100**
- Required floor: problem intensity, willingness to pay, and distribution must
  each be at least 50

Cycle 1 improves release-pipeline readiness and closes an authorization
boundary defect. It does **not** create a public notarized download, paying
customers, or usage-retention evidence. Those missing facts remain the main
reason the product is below the threshold.

## Method

The score is the equal-weight mean of seven dimensions. Public product facts
and captured repository evidence constrain each score. Point changes are
explicit inference, not measured market outcomes.

| Dimension | Baseline | Cycle 1 | Evidence and interpretation |
|---|---:|---:|---|
| Problem intensity | 50 | **50** | Established launchers and file utilities confirm recurring demand, but PathShelf has no interview, activation, or retention data. |
| Differentiation | 58 | **58** | Local-only operation, explicit folder grants, and no global index remain a useful privacy wedge. Cycle 1 does not broaden that wedge. |
| Usability | 63 | **63** | The panel remains fast and focused. The authorization guard prevents an invalid transition but does not materially improve first-use discovery. |
| Trust/privacy | 88 | **90** | Path-bar navigation now preserves the active Favorite permission boundary before URL, filter, history, visible-item, or scope mutation. |
| Reliability | 62 | **68** | A deterministic 28th panel contract, native smoke marker, AppKit capture, OS-level screenshot, 125-contract suite, and fail-closed package checks reduce known failure risk. Public field reliability is still unknown. |
| Willingness to pay | 40 | **40** | Alfred and Raycast provide category price anchors, not proof that users will pay for PathShelf's narrower workflow. No offer or conversion result exists. |
| Distribution | 24 | **32** | A manual Developer ID/notarization workflow and verified local-QA archive now exist. No credentials were used, no workflow was run, and no public notarized binary was published. |

Arithmetic: `(50 + 58 + 63 + 90 + 68 + 40 + 32) / 7 = 57.3`.

## What cycle 1 shipped

### Distribution readiness

- Local packaging refuses an ad-hoc app unless the operator explicitly opts
  into local QA mode.
- The QA zip is checksummed, extractable, arm64, and code-signature verifiable.
- A manual GitHub workflow fails when required secrets are absent, imports a
  Developer ID certificate, signs with hardened runtime, submits to Apple
  notarization, staples and assesses the app, then uploads only the verified
  candidate.
- The workflow does not create a tag or GitHub Release.
- The retained QA archive is labeled `distribution=local-qa-only`.

This is pipeline readiness, not distribution proof.

### Permission-bound path navigation

- A path component outside the active Home/configured/Favorite root is rejected
  before state or security-scope mutation.
- RED evidence shows the previous implementation escaped to a sibling
  `Outside` directory.
- GREEN evidence includes 28/28 panel contracts,
  `SMOKE pathBarBoundaryPreserved=true`, an in-process AppKit capture, and an
  independent OS-level AppleScript/CoreGraphics screenshot.

## Objective gaps

### 1. Public install trust

**Current gap:** there is still no downloadable Developer ID-signed,
notarized, stapled release.

**Required evidence:**

1. Authorized maintainer configures release secrets.
2. Manual binary candidate workflow succeeds on the exact protected-main SHA.
3. `spctl`, stapler validation, checksum, and clean-machine launch pass.
4. A release is published only after explicit authorization.

Expected score effect after real evidence: distribution **32 → 55**, overall
approximately **+3.3**.

### 2. Willingness-to-pay proof

**Current gap:** competitor pricing demonstrates a paid category, not demand
for PathShelf.

**Validation plan:**

1. Test one clearly stated one-time-license hypothesis against the narrow
   privacy-first workflow.
2. Recruit at least 20 target users who repeatedly switch among project,
   download, and reference folders.
3. Run a two-week beta with no passive telemetry; collect opt-in activation,
   weekly-use, and purchase-intent responses.
4. Require at least 50% week-two active use and at least 20% explicit paid
   intent before raising willingness to pay to 50.

Expected score effect if measured: willingness to pay **40 → 55**, overall
approximately **+2.1**.

### 3. First-use Favorite discoverability and keyboard access

**Current gap:** the highest-value controllable product gap is now Favorites
discovery and accessibility. Add actions remain context-menu-led, Return is
not wired for sidebar activation, and disclosure/location rows lack complete
VoiceOver semantics.

**Next implementation cycle:**

- Put an obvious native add action in the empty/default Favorites surface.
- Make Return activate the selected Favorite.
- Expose expanded/collapsed state and explicit Favorite row labels.
- Keep the panel minimal; do not add a global index or broad toolbar.

Expected score effect after verified implementation: usability **63 → 72** and
reliability **68 → 71**, overall approximately **+1.7**. This alone cannot
reach 70; it is the next local improvement while distribution and demand
evidence require authorized external action.

## Evidence

Repository evidence:

- `.omo/evidence/market-cycle-1/red/README.md`
- `.omo/evidence/market-cycle-1/distribution/README.md`
- `.omo/evidence/market-cycle-1/path-boundary/README.md`
- `.omo/evidence/market-cycle-1/final/README.md`

Public sources:

1. [PathShelf README](https://github.com/achieve0410/PathShelf/blob/main/README.md)
2. [PathShelf security model](https://github.com/achieve0410/PathShelf/blob/main/SECURITY.md)
3. [Raycast File Search](https://www.raycast.com/core-features/file-search)
4. [Raycast pricing](https://www.raycast.com/pricing)
5. [Alfred Powerpack pricing](https://www.alfredapp.com/powerpack/)
6. [Apple notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
7. [GitHub Actions artifacts](https://docs.github.com/actions/using-workflows/storing-workflow-data-as-artifacts)

## Conclusion

PathShelf is technically credible and meaningfully privacy-oriented, but
**57/100 is below the 70/100 stop threshold**. The improvement loop must
continue. The next controllable cycle is Favorite discovery and keyboard /
VoiceOver access; real market-value closure still requires a notarized public
binary and measured demand.
