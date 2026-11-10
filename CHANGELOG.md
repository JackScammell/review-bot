# Changelog

All notable changes to review-bot are recorded here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versioning: callers use `v1`, a moving tag that follows the latest release. There
are no numbered releases; each release gets its own dated section below, naming the
commit `v1` was moved to. Anything that would break an existing caller file goes to a
new tag, `v2`, instead. `[Unreleased]` lists what is on `main` but not yet on `v1`.

## [Unreleased]

### Added

- `LICENSE` (MIT), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` with the
  bot's threat model, and this changelog.
- `docs/` pages for setup, configuration and how the bot works. The README is now a
  short landing page with an illustrative review and a diagram.
- Tests: `tests/test_review_bot.py` (panel choice, inline-comment line mapping,
  mention scrubbing, cost, rendering) and `tests/test_scripts.sh` (tier choice,
  budget ladder and pace, ledger writes). Neither needs an API key or extra packages.
- CI (`.github/workflows/ci.yml`): shellcheck, actionlint and both test suites on
  every push and pull request, with read-only permissions and SHA-pinned actions.
- Issue forms, a pull request template and a `.gitignore`.
- Dependabot updates for the GitHub Actions this repo pins.

### Changed

- Comments in `examples/standalone.yml` and `scripts/install.sh` no longer name
  specific organisations or systems.
- `examples/standalone.yml` drops its unused `BUDGET` setting (it has no ledger).

### Fixed

- A ledger that is no longer a JSON object of months is now treated as unreadable (single reviews
  only) instead of as empty, and recording a run's cost fails at once with an error
  saying so. Before, recording a run's cost replaced it with a fresh ledger and lost
  the month's history. An empty or missing `ledger.json` still starts a fresh ledger.
- A PR that changes only `requirements*.txt` files no longer counts as
  documentation-only, so it gets the full council rules.
- The workflow's checkouts no longer leave the workflow token in the workspace.

### Removed

- A compiled Python file that had been committed by mistake.

## [v1][v1-2026-11-10] - 2026-11-10

First published version, at commit e7b7ed2. Built and changed over the same day.

### Added

- Reusable workflow (`.github/workflows/review.yml`) and a short caller
  (`examples/caller.yml`) so many repos share one bot and one budget.
- Two tiers: a single review for small, low-risk PRs, and a council of Parliament of
  Chaos reviewer personas, chosen by what the PR touches, merged by a chair.
- Reviews when a PR is opened, reopened or marked ready, and on `/review` or
  `/council` comments from owners, organisation members and collaborators.
- Optional shared spend ledger in a gist, with a budget ladder that steps down from
  councils to single reviews to none as the month's budget fills, and paces spending
  across the month.
- Follow-up rounds: the bot reads its previous review and the changes since.
- Per-repo rules in `.github/review-bot-rules.md`, read from the base branch.
- Self-contained workflow (`examples/standalone.yml`) for repos whose CI refuses jobs
  from external reusable workflows.
- `DRY_RUN=1` mode that gathers a PR and prints what would be sent, without calling
  the API or posting.

### Changed

- Reviews now call the Claude API directly instead of running Claude Code in the
  workflow, so API credit pays for them, and post as `github-actions[bot]` with no
  GitHub App.
- Re-reviews are asked for with a comment; label triggers were removed.
- The caller passes `ANTHROPIC_API_KEY` by name, because `secrets: inherit` does not
  reach a workflow owned by another account.
- House rules: proportionate findings, no objections to the amount of test code, no
  tagging people and no quoting personal data.

[Unreleased]: https://github.com/JackScammell/review-bot/compare/v1...HEAD
[v1-2026-11-10]: https://github.com/JackScammell/review-bot/tree/e7b7ed2176f86ae42d258975d7d6d0c996dcf39c
