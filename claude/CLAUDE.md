## Commits
- Omit `Co-Authored-By: Claude ...` trailers on all new commits. Preserve only if already present when rebasing.

## Session Specs & Plans
- Never `git add` or commit session specs or plans, unless the project has explicit rules allowing it or the user explicitly requests it.

## Development Workflow
- RED/GREEN/REFACTOR TDD cycle — bug fixes and features always start with failing tests that cover all specs. Production code is written against failing tests.
