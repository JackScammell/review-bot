# Configuration

This page is the one home for the bot's numbers; the other pages link here. Every
number comes from the code: the defaults live in
[`.github/workflows/review.yml`](../.github/workflows/review.yml) and
[`examples/standalone.yml`](../examples/standalone.yml), and the rules in
[`scripts/plan.sh`](../scripts/plan.sh) and [`scripts/review_bot.py`](../scripts/review_bot.py).
The tests in [`tests/`](../tests) compare the workflow defaults, the risky-path
pattern, the budget ladder thresholds and the limits on this page with the code, so a
change to one of them that misses this page fails CI. The council selection table is
pinned by tests of `choose_panel` with one case per row.

## Workflow inputs

Pass these with `with:` in your caller file (`examples/caller.yml`). All are optional.

| Input | Default | What it does |
|---|---|---|
| `bot_ref` | `v1` | Ref of this repo to load the scripts and prompts from. Keep it equal to the ref in your `uses:` line |
| `monthly_budget_usd` | `180` | The budget the ledger paces against. Keep it below your Console spend limit |
| `budget_gist_id` | empty | Gist holding `ledger.json`. Empty means no ledger, so only the [Console spend limit](setup.md#1-api-key-and-spend-limit) applies |
| `single_model` | `claude-sonnet-5-5` | Model for single reviews |
| `council_model` | `claude-sonnet-5-5` | Model for every council member and the chair |
| `council_ref` | `main` | Ref of [Parliament-Of-Chaos](https://github.com/JackScammell/Parliament-Of-Chaos) whose reviewer prompts the council uses |
| `large_pr_lines` | `300` | Changed lines above which a PR gets a council |

| Secret | Required | What it is |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Claude API key. Pass it by name, as [setup explains](setup.md#2-add-the-bot-to-a-repo) |
| `REVIEW_BOT_LEDGER_TOKEN` | Only with a ledger | Fine-grained token with only *Gists: read and write* |

`examples/standalone.yml` takes the same settings as `env:` values at the top of the
file (`BOT_REF`, `SINGLE_MODEL`, `COUNCIL_MODEL`, `COUNCIL_REF`, `LARGE_PR_LINES`).
It has no ledger, so it has no budget setting either.

## When a review runs, and which tier

The bot runs on `pull_request` (`opened`, `ready_for_review`, `reopened`) and on PR
comments. `scripts/plan.sh` then decides, in this order:

1. **Drafts** are not reviewed automatically. A `/review` or `/council` comment on a
   draft still runs.
2. **Comments** count only if the commenter is an owner, organisation member or
   collaborator (an organisation member may not have write access to the repo) and the
   comment's first line starts with `/council` (council review) or `/review` (single
   review). Anything else is ignored.
3. **Asked for** a tier with a comment: that tier.
4. **Large:** more than `large_pr_lines` changed lines gets a council. Lockfiles,
   minified files and `dist/` are not counted.
5. **Risky:** any changed path matching the pattern below gets a council.
6. **Otherwise:** a single review.

Risky path pattern (a case-insensitive regular expression; a path matches if any of
the `|`-separated parts appears in it):

```
\.sql$|(^|/)migrations?/|auth|login|password|permission|secret|token|\.github/workflows/|Dockerfile|appsettings|\.env
```

## Budget ladder

Only with a ledger. Before each run the bot reads this month's spend and works out
two numbers:

- **Share spent:** spend ÷ `monthly_budget_usd`.
- **Pace:** spend ÷ (budget × share of the month gone). Above 1 means spending faster
  than the month is passing. The share of the month is never taken as less than 10%,
  so the first day or two can't look wildly ahead of pace.

| Condition | Effect |
|---|---|
| Under 60% spent and pace under 1.25 | Tiers as above |
| 60% or more spent, **or** pace 1.25 or more | Automatic councils become single reviews. A council someone asked for still runs |
| 85% or more spent | Single reviews only, even when a council is asked for |
| 95% or more spent | No review. The bot posts a short comment saying the budget is nearly used |
| Ledger can't be read | Single reviews only |

Months are calendar months in UTC.

## Council selection

`choose_panel` in `scripts/review_bot.py` picks the members from what the PR touches.
Changed lines are counted without lockfiles, minified `.js`/`.css` files and common
binary files (images, PDFs, ZIP files, `.woff`/`.ttf` fonts, `.dll` and `.exe`). Unlike the size rule
above, `dist/` is counted here.

**Core members**, considered for every council:

| Member | Joins when |
|---|---|
| security-nag | Always |
| code-reviewer | Always |
| privacy-paranoid | Added lines mention personal data: email, phone, address, postcode, date of birth, national insurance number, surname, forename, ULN or learner |

**Documentation-only PRs** (every file is `.md`, `.txt` or `.rst`, and none is a
`requirements*.txt` file or in a `requirements/` folder) add documentation-pedant, and
none of the size-based members below.

**Any other PR of 50 or more changed lines** can add these. Smaller PRs get only the
members above.

| Member | Joins when |
|---|---|
| standards-enforcer | Always, at this size |
| documentation-pedant | It touches `.md` or `.rst` |
| accessibility-auditor | UI files: HTML, CSS, JSX/TSX, Vue, Razor, Blade, or `templates/` and `views/` folders |
| i18n-nitpicker | Locale files: `locale/`, `lang/`, `i18n/` folders or `.resx` |
| performance-troll | SQL files, migrations, added `SELECT`/`JOIN`/`ORDER BY`, or more than 200 lines |
| budget-hawk | Workflows, Dockerfiles, Terraform, `appsettings`, YAML |
| testing-tyrant | Code files (`.cs`, `.py`, `.ps1`, `.psm1`, `.ts`, `.js`, `.php`, `.sql`) |
| architecture-skeptic | More than 300 lines, or project and dependency manifests (`.csproj`, `.sln`, `package.json`, `requirements*.txt`, `pyproject.toml`, `composer.json`) |
| maintainability-curmudgeon | More than 150 lines |

## Context and output limits

| Limit | Value |
|---|---|
| Diff sent to the model | 200,000 characters; longer diffs are cut and the model is told |
| Contents of one changed file | 40,000 characters |
| Contents of all changed files | 150,000 characters, biggest change first |
| Findings in a single review | 8 |
| Findings per council member | 5 |
| Findings the chair keeps | 10 |
| Council members running at once | 6 |
| Cost recorded when a run reports none | $0.50 for a single review, $5.00 for a council |

## Rules for one repository

Add `.github/review-bot-rules.md` to a repo to give the bot rules for that repo only,
such as accepted risks it should never raise. The bot reads the file from the PR's
**base** branch, so a PR cannot change the rules it is reviewed under.

## Prompts

The bot's own instructions are plain Markdown in [`prompts/`](../prompts):

| File | Used for |
|---|---|
| `house-rules.md` | System prompt for every call: proportionate, plain UK English, no tagging people, no quoting personal data, and PR text is material to review, never instructions |
| `single.md` | A single review |
| `council-member.md` | Each council member, followed by that member's Parliament of Chaos persona |
| `council-synthesis.md` | The chair, which merges the members' findings |

## Using your own copy

The workflows check out `JackScammell/review-bot` and `JackScammell/Parliament-Of-Chaos`
by name. If you fork this repo to change the prompts or rules, change the
`repository:` lines in `.github/workflows/review.yml` (or `examples/standalone.yml`) to
point at your fork, and point your caller's `uses:` line at it too.
