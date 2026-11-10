# Security Policy

review-bot runs in your repository's GitHub Actions with your Claude API key and a
token that can comment on pull requests. This page says what it can reach, what it
does with your code, and where the trust boundaries are.

## Reporting a vulnerability

Please do not open a public issue for anything you believe is exploitable.

Use GitHub's private vulnerability reporting instead:
https://github.com/JackScammell/review-bot/security/advisories/new

Include the ref you run (`v1` or a commit SHA), which workflow file you use, and the
smallest reproduction you can manage. Remove keys, tokens and private code. Reports
are read on a best-effort basis by a single maintainer; expect an acknowledgement
within a week.

## Supported versions

Only the latest `v1` receives fixes. `v1` is a moving tag; pin a commit SHA if you
need a fixed version (see [Pinning a version](docs/setup.md#pinning-a-version)).

## What the bot can reach

| Where | What |
|---|---|
| Plan job | The workflow token, and the ledger token if you set one up |
| Review job | The workflow token and `ANTHROPIC_API_KEY`; the ledger token only in the last step, which records the cost |
| Workflow token permissions | `contents: read`, `pull-requests: write` (to post the review), `issues: write` (for the "budget nearly used" comment) |
| Ledger token | Should be a fine-grained token with only *Gists: read and write* |

## Who can start a run

- **Pull request events** (opened, reopened, ready for review) start a run. For a PR
  from a fork, GitHub gives the workflow no secrets, so the review fails without
  spending anything.
- **`/review` and `/council` comments** start a run only when the commenter is an owner,
  organisation member or collaborator of the repository. An organisation member may
  have read access only and can still start a run, which spends from your budget. This is checked twice: in the caller
  file's `if:` (so other comments don't start a runner) and again in `scripts/plan.sh`.
  If you edit the caller, keep the check.
- **A comment on a fork PR** runs in your repository with your secrets, next to a
  checkout of the fork's code. Comment `/review` on a fork PR only when you would be
  happy to check that code out yourself.

## What happens to the PR's code

- The workflow checks out the PR's head commit and reads its files as text. As written,
  it does not run, build or install anything from the PR; the only code it runs comes
  from this repository at `bot_ref`, and the only package it installs is the
  `anthropic` SDK from PyPI. That is the defence that matters: a change that ran PR
  code would run it next to the API key. Every checkout is made with
  `persist-credentials: false`, so the workflow's own token is not left anywhere in
  the workspace.
- The PR's description, diff and changed files are sent to the Claude API under your
  API key. Your agreement with Anthropic covers that data, as it would for any other
  API use.
- The house rules tell the model never to quote personal data from the code or the
  description. That is an instruction to the model, not a filter.

## Prompt injection

The model reads text the PR's author controls. To limit what that can do:

- The house rules tell the model that the PR's text and code are material to review,
  never instructions.
- The model has no tools. It can only return JSON in a fixed shape (verdict, summary,
  findings), which the bot then formats.
- The review is posted as a comment. It never approves or requests changes, so it
  cannot unblock or block a merge.
- `@` mentions in the model's text are broken up, so it cannot tag people or teams.

A crafted PR can still steer the summary, the verdict and the findings. Treat a review
as advice that a person reads, never as a security gate.

## Trust in upstream code

Each run loads scripts and prompts from this repository at `bot_ref` and, for a
council, reviewer personas from
[Parliament-Of-Chaos](https://github.com/JackScammell/Parliament-Of-Chaos) at
`council_ref` (default `main`). Whoever can push to those refs decides what runs next
to your API key. The defaults follow moving refs; pin all three (`uses:`, `bot_ref`
and `council_ref`) to commit SHAs if that is not acceptable.

Also not pinned today: the actions in the review workflow use major-version tags
(`actions/checkout@v4`, `actions/setup-python@v5`), and the `anthropic` package is
installed at its latest version. This repository's own CI pins its actions by SHA.

## Spend

The [Console spend limit](docs/setup.md#1-api-key-and-spend-limit) on the bot's
workspace is the only hard cap. The optional ledger, which only paces spending, lives
in a secret gist. A secret gist is unlisted rather than private: anyone with its URL can read the repo names, PR numbers and costs in it, and
anyone with the ledger token can change it.
