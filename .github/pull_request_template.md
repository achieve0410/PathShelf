## Outcome

Describe the user or maintainer outcome and the smallest scope that delivers it.

## Evidence

- Failing-first proof or characterization test:
- Green verification command:
- Real-surface QA:

Pure documentation changes should provide review and rendered/read evidence
instead of tests that pin prose.

## Risk review

- [ ] File-operation and permission boundaries are unchanged or explicitly tested.
- [ ] No app-owned network client, telemetry, account, or update path was added.
- [ ] No polling or hidden-panel background work was added.
- [ ] Destructive behavior remains Trash-only and replacement remains explicit.
- [ ] Logs and fixtures contain no credentials, bookmark data, or private paths.

## Required checks

- [ ] `swift build --arch arm64`
- [ ] `bash BuildSupport/test.sh`
- [ ] Relevant smoke and audit scripts
- [ ] Documentation and `CHANGELOG.md` updated when applicable

## AI assistance

- [ ] I reviewed and understand all submitted changes, including any AI-assisted content.
