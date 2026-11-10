# Contributing to review-bot

Thanks for taking an interest. This is a small project with one maintainer, so the
process is light: open an issue to talk about anything bigger than a fix, then send a
pull request.

## What's in the repo

```
.github/workflows/review.yml   Reusable workflow that callers use
.github/workflows/ci.yml       CI for this repo (lint + tests, no secrets)
examples/caller.yml            The few lines a repo adds to use the bot
examples/standalone.yml        Self-contained alternative to the caller
scripts/plan.sh                Decides whether to review and at which tier
scripts/ledger.sh              Reads and writes the shared spend ledger
scripts/record-cost.sh         Adds a run's cost to the ledger
scripts/review_bot.py          Gathers the PR, calls the Claude API, posts the review
scripts/install.sh             Sets the bot's secrets on several repos
prompts/                       The model's instructions, in plain Markdown
tests/                         Unit tests (Python) and script tests (bash)
docs/                          Setup, configuration and how it works
```

## Running the checks

You need Python 3.12 or later, bash, `jq` and, for linting,
[shellcheck](https://www.shellcheck.net/) and
[actionlint](https://github.com/rhysd/actionlint). No Python packages are needed for
the tests.

```bash
python3 -m unittest discover -s tests -v       # review_bot.py helpers
bash tests/test_scripts.sh                     # plan.sh and record-cost.sh
shellcheck -x --source-path=SCRIPTDIR scripts/*.sh tests/*.sh
actionlint .github/workflows/*.yml examples/*.yml
```

CI runs the same commands on every push and pull request.

The script tests put fake `gh` and `date` commands first on `PATH`, so they never
touch GitHub and always see the same month. If you add a new `gh` or `date` call to
the scripts, the fakes will refuse it until you teach them about it.

## Trying a change on a real PR

A dry run gathers a PR and prints the context and council it would use, without
calling the API or posting. From a checkout of the PR's branch:

```bash
git clone -b <your-branch> <your fork URL> .review-bot
DRY_RUN=1 TIER=council PR=<number> REPO=<owner>/<repo> python3 .review-bot/scripts/review_bot.py
```

For a live check, point a test repo's caller at your branch (`uses: ...@<branch>` and
`bot_ref: <branch>`) and open a PR there. The workflows load scripts from
`JackScammell/review-bot` by name, so on a fork change the `repository:` lines first
(see [Using your own copy](docs/configuration.md#using-your-own-copy)). Say in your
pull request what the live check cost.

## Guidelines

- **Keep behaviour and docs together.** If you change a default, threshold, trigger or
  input, update [`docs/configuration.md`](docs/configuration.md) and the tests in the
  same pull request.
- **Change both workflows together.** `examples/standalone.yml` is a self-contained
  copy of `.github/workflows/review.yml`. A change to one almost always belongs in the
  other. Dependabot keeps this repo's own CI actions current; the actions in the
  review workflows and `examples/` are updated by hand.
- **Mind the cost.** Anything that adds calls, members or context makes every review
  dearer. Say roughly by how much.
- **Prompts** are written in plain UK English and stay short. The house rules apply to
  every call, so changes there affect every repo using the bot.
- **Shell scripts** in `scripts/` use `set -euo pipefail`, and every script must pass
  shellcheck. `tests/test_scripts.sh` leaves out `-e` on purpose, so one failed check
  is counted rather than stopping the run.
- **Python** uses only the standard library plus `anthropic`, which is imported inside
  the functions that call the API so the rest can be tested without it.
- **Workflows** keep the smallest permissions that work. CI must never gain secrets or
  write permissions.

## Pull requests

1. Branch from `main`.
2. Make the change with its tests and docs.
3. Add a line under "Unreleased" in [`CHANGELOG.md`](CHANGELOG.md).
4. Open the pull request and fill in the template. CI must be green.

## Releases

Callers use the `v1` tag. A release moves it to a new commit on `main`, after which
every repo on `v1` picks up the change on its next run:

```bash
git tag -f v1 <commit> && git push -f origin v1
```

At that point the "Unreleased" changelog entries move into a new section headed
`## [v1][v1-<date>] - <date>`. Add the matching `[v1-<date>]:` line at the bottom of
the changelog, linking to the commit the tag now points to. For a second release on
the same day, add a suffix to the label, such as `v1-<date>-2`.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Licence

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
