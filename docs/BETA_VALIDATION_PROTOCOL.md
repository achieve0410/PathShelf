---
minimum_cohort_size: 20
follow_up_days: 14
minimum_week_two_active_rate: 0.5
minimum_paid_intent_rate: 0.2
one_time_price_usd: 20
---

# PathShelf Beta Validation Protocol

## Purpose

This protocol measures whether the privacy-first Favorite workflow solves a
repeated problem and supports a one-time paid product. Repository completeness
does not count as demand evidence.

PathShelf does not collect telemetry, create an account, run an app-owned
network service, or upload feedback automatically. A participant chooses the
`Send Beta Feedback…` menu command, reviews the public GitHub form, and decides
whether to submit it.

## Cohort

Recruit at least 20 macOS users who repeatedly switch among a small set of
project, download, or reference folders. Do not count maintainers, automated
submissions, duplicate participants, or people who did not use the beta for the
full two-week period.

## Procedure

1. Give each participant the same notarized beta candidate and install guide.
2. Ask them to add at least one Favorite and use PathShelf during normal work.
3. Do not prompt during the two-week period or collect passive activity.
4. After 14 days, ask each participant to submit the structured beta feedback
   issue.
5. Exclude submissions containing paths, filenames, credentials, personal
   data, or other sensitive information instead of copying that content into
   analysis.

## Decision rules

Count a participant as week-two active when they report using PathShelf on at
least two days during the second week.

Count explicit paid intent only when the participant selects that they would
buy a one-time license at US$20. Lower-price interest, indecision, and
non-purchase do not satisfy the paid-intent threshold.

Raise willingness-to-pay to at least 50 only when:

- the valid cohort contains at least 20 participants;
- at least 50% are week-two active; and
- at least 20% report explicit one-time paid intent at US$20.

Distribution remains below 50 until the tested beta is Developer ID-signed,
notarized, stapled, downloadable, and independently launch-verified. A local QA
archive or an unexecuted release workflow is not distribution proof.

## Privacy and reporting

Publish aggregate counts and rates only. Do not publish or retain participant
paths, filenames, credentials, personal data, or free-form private notes.
Record excluded-submission counts and the exact protected-main SHA tested so
the result remains auditable.
