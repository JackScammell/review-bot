# review-bot

Claude PR reviews across several repos from one shared monthly budget.

## How it decides

| Tier | When | Model |
|---|---|---|
| Single review | Small, low-risk PRs; `/review` comment; `review-bot:review` label | Sonnet 5.5 |
| Council (`/chaos:parliament-review`, tiered panel) | Over 300 changed lines, risky paths (SQL, migrations, auth, workflows, config); `/council`; `review-bot:council` label | Sonnet 5.5 (reviewers inherit) |
| None | Drafts, `review-bot:skip`, comments from people without write access | n/a |

It runs when a PR is opened or marked ready, not on every push. After a round of fixes, comment `/review` or `/council` to re-run.

### Budget ladder (shared across every repo)

Each run's cost is added to `ledger.json` in one gist. Before each run:

- **Under 60% of the budget used, and on pace:** tiers as above.
- **60–85%, or spending ahead of pace for the month:** councils run only when asked for.
- **85–95%:** single reviews only.
- **95% and over:** no review; the bot comments on the PR instead.

The hard stop is the **Console spend limit** on the bot's workspace. Set it a little above `monthly_budget_usd` (default 180, cap e.g. 190). The ledger only paces spending; it can miss a run if two finish at the same moment.

## One-time setup

1. **Anthropic Console:** create a `review-bot` workspace, set its monthly spend limit, and create an API key in it.
2. **Ledger gist:** create a secret gist with a file `ledger.json` containing `{}`. Put its ID in `budget_gist_id` in `.github/workflows/review.yml`.
3. **Ledger token:** a fine-grained personal access token with only *Gists: read and write*.
4. **Claude GitHub App:** install it on your account and on the ACT-Training org (an org admin has to approve), for the repos that will use the bot.
5. **Publish this repo** (public, so ACT-Training repos can call it), then tag it: `git tag v1 && git push origin v1`.

## Adding a repo

```bash
ANTHROPIC_API_KEY=... REVIEW_BOT_LEDGER_TOKEN=... scripts/install.sh JackScammell/pr-watcher
```

Then add `examples/caller.yml` to the repo as `.github/workflows/review-bot.yml`. Optional: add `.github/review-bot-rules.md` with rules specific to that repo, such as accepted risks the bot must never raise.

For ACT-Training, set the two secrets once at org level and choose the repos, instead of setting them per repo.

## Changing it

Edit prompts or thresholds here, then move the tag (`git tag -f v1 && git push -f origin v1`). Every repo picks up the change on its next run.
