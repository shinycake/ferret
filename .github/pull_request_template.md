## Summary

<!-- What changed, and which ticket it is. -->

## Ticket

<!-- T0, T1, … -->

## Proof checklist

CI on `macos-latest` must be green. Link the run and the uploaded artifacts. Screenshots, when a ticket requires them, come only from the `cacheDisplay` harness.

- [ ] CI run: <!-- https://github.com/shinycake/ferret/actions/runs/… -->
- [ ] `proof` artifact (logs, test results, and any PNG snapshots)
- [ ] `Ferret-app` artifact, when this ticket produces an app
- [ ] Unit tests passed (`proof/core-tests.log` and `proof/core-tests.xml`)
- [ ] `proof/xcodebuild.log` shows a successful build
- [ ] Job summary shows this ticket's acceptance evidence
- [ ] No `CGWindowListCreateImage`, `SCScreenshotManager`, or `SCStream` captures

## Acceptance evidence

<!-- Paste the job-summary lines or artifact paths that show the acceptance criteria. -->

## Test plan

- [ ] `swift test --package-path Packages/FerretCore`
- [ ] GitHub Actions workflow `CI` / `build-test`
