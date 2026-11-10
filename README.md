# review-bot

Claude PR reviews across several repos from one shared monthly budget. Reviews call the Claude API directly (`scripts/review_bot.py`), not Claude Code, so API-only credit covers them.

## How it decides

| Tier | When | Model |
|---|---|---|
| Single review | Small, low-risk PRs; a `/review` comment | Sonnet 5.5 |
| Council (Parliament of Chaos reviewer prompts, one API call each, then a synthesis call) | Over 300 changed lines, risky paths (SQL, migrations, auth, workflows, config); a `/council` comment | Sonnet 5.5 |
| None | Drafts, comments from people without write access | n/a |

It runs when a PR is opened or marked ready, not on every push. To review again after a round of fixes, comment `/review` or `/council` on the PR (the command must start the comment).

### Budget ladder (optional, shared across every repo)

Without a ledger the bot uses the tiers above and the Console spend limit is the only stop. With one, each run's cost is added to `ledger.json` in one gist. Before each run:

- **Under 60% of the budget used, and on pace:** tiers as above.
- **60–85%, or spending ahead of pace for the month:** councils run only when asked for.
- **85–95%:** single reviews only.
- **95% and over:** no review; the bot comments on the PR instead.

The hard stop is the **Console spend limit** on the bot's workspace. Set it a little above `monthly_budget_usd` (default 180, cap e.g. 190). The ledger only paces spending; it can miss a run if two finish at the same moment.

## One-time setup

1. **Anthropic Console:** create a `review-bot` workspace, set its monthly spend limit, and create an API key in it.
2. **Ledger gist (optional):** create a secret gist with a file `ledger.json` containing `{}`. Put its ID in `budget_gist_id` in `.github/workflows/review.yml`.
3. **Ledger token (only with a gist):** a fine-grained personal access token with only *Gists: read and write*.
4. **No GitHub App needed:** reviews post with the workflow's own token, as `github-actions[bot]`.
5. **Publish this repo** (public, so ACT-Training repos can call it), then tag it: `git tag v1 && git push origin v1`.

## Adding a repo

```bash
gh secret set ANTHROPIC_API_KEY --repo JackScammell/pr-watcher   # prompts for the value
# or, for several repos with a ledger: ANTHROPIC_API_KEY=... REVIEW_BOT_LEDGER_TOKEN=... scripts/install.sh JackScammell/pr-watcher
```

Then add `examples/caller.yml` (it passes `ANTHROPIC_API_KEY` explicitly; `secrets: inherit` does not work across accounts) to the repo as `.github/workflows/review-bot.yml`. Optional: add `.github/review-bot-rules.md` with rules specific to that repo, such as accepted risks the bot must never raise.

For ACT-Training, set the two secrets once at org level and choose the repos, instead of setting them per repo.

## Changing it

Edit prompts or thresholds here, then move the tag (`git tag -f v1 && git push -f origin v1`). Every repo picks up the change on its next run.

## How a review works

1. Gathers the PR: description, full diff, the changed files' new contents, the repo's `.github/review-bot-rules.md` (read from the base branch, so a PR can't rewrite its own rules) and the bot's previous review with the changes since.
2. **Single:** one structured call. **Council:** the security and code-quality reviewers always, plus others chosen by what the PR touches; the first runs alone to cache the shared context, the rest run in parallel and read it at about a tenth of the price; then one synthesis call.
3. Posts one PR review (comment only, never approve or block) with inline comments on lines in the diff, and a hidden marker so the next round knows what it already reviewed.
4. Reports its cost, which the ledger records if one is set up.

Try it without spending anything: `DRY_RUN=1 TIER=council PR=<n> REPO=<owner/name> python3 scripts/review_bot.py` from a checkout of the PR.
