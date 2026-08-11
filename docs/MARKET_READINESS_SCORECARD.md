# PathShelf Market Readiness Scorecard

Checked: 2026-08-12

## Decision

PathShelf has a credible product wedge, but it is not yet proven to have
sufficient market value.

- Baseline: **55/100**
- After market cycle 1: **57/100**
- After market cycle 2: **59/100**
- Sufficient-market-value threshold: **70/100**
- Required floor: problem intensity, willingness to pay, and distribution must
  each be at least 50

Cycle 2 makes the core Favorite workflow discoverable from the primary panel,
keyboard-operable, and explicit to VoiceOver. It does **not** create a public
notarized download, paying customers, or usage-retention evidence. Those
missing facts remain the main reason the product is below the threshold.

## Method

The score is the equal-weight mean of seven dimensions. Public product facts
and captured repository evidence constrain each score. Point changes are
explicit inference, not measured market outcomes.

| Dimension | Baseline | Cycle 1 | Cycle 2 | Evidence and interpretation |
|---|---:|---:|---:|---|
| Problem intensity | 50 | 50 | **50** | Established launchers and file utilities confirm recurring demand, but PathShelf has no interview, activation, or retention data. |
| Differentiation | 58 | 58 | **58** | Local-only operation, explicit folder grants, and no global index remain a useful privacy wedge. Cycle 2 does not broaden that wedge. |
| Usability | 63 | 63 | **72** | The primary panel now has a visible native `Add Favorite…` action, and Return activates the selected Favorite. |
| Trust/privacy | 88 | 90 | **90** | The permission boundary remains guarded; cycle 2 adds no new data collection or network access. |
| Reliability | 62 | 68 | **71** | RED-to-GREEN native smoke covers add-control wiring, awaited keyboard activation, and accessibility state. All 125 contracts and existing smoke markers remain green. |
| Willingness to pay | 40 | 40 | **40** | Alfred and Raycast provide category price anchors, not proof that users will pay for PathShelf's narrower workflow. No offer or conversion result exists. |
| Distribution | 24 | 32 | **32** | A manual Developer ID/notarization workflow and verified local-QA archive exist, but no notarized public binary was published. |

Arithmetic: `(50 + 58 + 72 + 90 + 71 + 40 + 32) / 7 = 59.0`.

## What cycle 2 shipped

### Favorite discovery and keyboard access

- The sidebar footer exposes a native `Add Favorite…` action with the
  `pathshelf.favorite.add` accessibility identifier.
- The action routes to the existing security-scoped folder chooser path.
- Return activates the selected Favorite and awaits the resulting navigation
  task in deterministic smoke coverage.

### VoiceOver semantics

- Group disclosure rows expose labels and `expanded` / `collapsed` values.
- Healthy Favorite rows identify themselves as Favorites.
- Unavailable Favorite rows expose their availability state without relying
  on icon color or styling alone.

RED evidence captured all three smoke markers as false before implementation.
GREEN evidence and the complete final run capture all three as true. Fresh
native AppKit screenshots show the add action without clipping or overlap.
Independent OS-level chooser capture was not accepted because the isolated QA
window remained 0×0 in WindowServer while a user-owned PathShelf process was
preserved; that limitation receives no score credit.

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

### 3. Measured activation and retention

**Current gap:** Favorite discovery and keyboard / VoiceOver access are now
implemented, but there is no evidence that target users complete setup,
activate the panel repeatedly, or retain the workflow.

**Required evidence:**

1. Publish an authorized notarized beta to a defined target cohort.
2. Record opt-in, privacy-preserving setup completion and weekly-use evidence.
3. Interview users who abandon setup and those who retain the workflow.
4. Use measured results rather than repository completeness to change problem
   intensity, willingness to pay, or retention-related reliability scores.

The next local cycle can make this experiment auditable and consent-based, but
cannot manufacture activation, retention, or willingness-to-pay outcomes.

## Evidence

Repository evidence:

- `.omo/evidence/market-cycle-1/red/README.md`
- `.omo/evidence/market-cycle-1/distribution/README.md`
- `.omo/evidence/market-cycle-1/path-boundary/README.md`
- `.omo/evidence/market-cycle-1/final/README.md`
- `.omo/evidence/market-cycle-2/red/README.md`
- `.omo/evidence/market-cycle-2/green/README.md`
- `.omo/evidence/market-cycle-2/final/README.md`
- `.omo/evidence/market-cycle-2/os/README.md`

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
**59/100 is below the 70/100 stop threshold**. The improvement loop must
continue. The next controllable cycle is an auditable, opt-in beta-validation
path; real market-value closure still requires an authorized notarized public
binary and measured demand.
