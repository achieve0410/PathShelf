# PathShelf Market Readiness Scorecard

Checked: 2026-08-12

## Decision

PathShelf has a credible product wedge, but it is not yet proven to have
sufficient market value.

- Baseline: **55/100**
- After market cycle 1: **57/100**
- After market cycle 2: **59/100**
- After market cycle 3: **59/100**
- Sufficient-market-value threshold: **70/100**
- Required floor: problem intensity, willingness to pay, and distribution must
  each be at least 50

Cycle 3 creates a consent-based public feedback entry and a fixed, auditable
two-week validation protocol without telemetry or automatic upload. It does
**not** create a public notarized download, paying customers, or
usage-retention evidence. Enabling evidence collection is not the evidence
itself, so no market-value dimension receives score credit in this cycle.

## Method

The score is the equal-weight mean of seven dimensions. Public product facts
and captured repository evidence constrain each score. Point changes are
explicit inference, not measured market outcomes.

| Dimension | Baseline | Cycle 1 | Cycle 2 | Cycle 3 | Evidence and interpretation |
|---|---:|---:|---:|---:|---|
| Problem intensity | 50 | 50 | 50 | **50** | Established launchers and file utilities confirm recurring demand, but PathShelf has no completed target-user cohort. |
| Differentiation | 58 | 58 | 58 | **58** | Local-only operation, explicit folder grants, no global index, and no telemetry remain a useful privacy wedge. |
| Usability | 63 | 63 | 72 | **72** | The primary panel has visible Favorite setup, keyboard activation, and VoiceOver semantics. The feedback menu does not change the core workflow score. |
| Trust/privacy | 88 | 90 | 90 | **90** | The permission boundary remains guarded; beta feedback is direct-user-action only, with no collection or automatic upload. |
| Reliability | 62 | 68 | 71 | **71** | The beta action and schema are verified, but field reliability still requires independent user operation over time. |
| Willingness to pay | 40 | 40 | 40 | **40** | A fixed US$20 hypothesis now exists, but no participant has reported paid intent and no conversion result exists. |
| Distribution | 24 | 32 | 32 | **32** | A manual Developer ID/notarization workflow and verified local-QA archive exist, but no notarized public binary was published. |

Arithmetic: `(50 + 58 + 72 + 90 + 71 + 40 + 32) / 7 = 59.0`.

## What cycle 3 shipped

### Consent-based evidence entry

- Both native menus expose `Send Beta Feedback…`.
- The command opens the public PathShelf GitHub issue form only after a direct
  user action.
- Native smoke invokes the production `NSMenu` action and verifies the exact
  HTTPS host, path, and template at the browser-adapter boundary.
- No telemetry, account, polling, automatic upload, or app-owned service was
  added.

### Auditable beta protocol

- The structured issue form records workflow frequency, Favorite setup,
  week-two use, one-time US$20 purchase intent, and explicit public/privacy
  consent.
- The protocol fixes the evidence gate at 20 valid target users, 14 days,
  50% week-two activity, and 20% explicit paid intent at US$20.
- `beta-feedback-audit.sh` parses those machine-consumed fields and thresholds
  and runs inside the complete test suite.

RED evidence captured the absent artifacts and smoke marker before production
implementation. GREEN and final evidence cover the schema, native menu action,
unchanged primary panel, complete regression suite, two independent GOOD
visual verdicts, and cleanup. These additions make future demand evidence
auditable but do not substitute for actual participants or payment behavior.

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

**Current state:** cycle 3 now provides the consent-based issue form, fixed
cohort thresholds, and native entry point. No valid participant result exists
yet.

**Required external evidence:**

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

1. A maintainer configures Developer ID/notarization credentials and publishes
   an independently launch-verified beta candidate.
2. At least 20 target users run that exact SHA for the full 14-day protocol.
3. Aggregate issue-form results satisfy the fixed activity and US$20 paid
   intent thresholds.
4. Use measured results rather than repository completeness to change problem
   intensity, willingness to pay, distribution, or field reliability.

No remaining repository-only change can manufacture these facts. Developer ID
credentials, public publication, elapsed cohort time, and independent user
responses are external state.

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
- `.omo/evidence/market-cycle-3/red/README.md`
- `.omo/evidence/market-cycle-3/green/README.md`
- `.omo/evidence/market-cycle-3/final/README.md`

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
**59/100 is below the 70/100 stop threshold**. Problem intensity is at its
minimum floor, but willingness to pay (**40**) and distribution (**32**) are
below their required floors. The controllable beta-validation entry is now
implemented. Further score movement requires an authorized notarized public
binary, 14 elapsed days, and measured target-user demand; these results must not
be inferred from shipped code.
