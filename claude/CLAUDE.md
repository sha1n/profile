## Commits
- Use Conventional Commits: `type(scope): summary` (feat, fix, chore, docs, refactor, test, …).
- Don't describe tests in commit messages, UNLESS the commit is entirely about testing.

## Session Specs & Plans
- Never `git add` or commit specs or plans under `docs/superpowers/` (the superpowers skill's scratch location), UNLESS the project has explicit rules allowing it or the user explicitly requests it. Specs and plans stored elsewhere are fine to commit.

## Communication
- Minimize output when my involvement isn't needed. For progress messages and status updates, state what you're about to do or just did in one or two sentences — skip the background story and step-by-step detail.
- Specs, plans, interviews, and interactive discussions stay clear and detailed as usual; only routine progress/status messages should be short and concise.

## Development Workflow
- RED/GREEN/REFACTOR TDD cycle — bug fixes and features always start with failing tests that cover all specs. Production code is written against failing tests.
