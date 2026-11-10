# Setup

The [quick start](../README.md#quick-start) gets one repo reviewed. This page covers
the rest: a spend cap, the optional ledger, many repos at once, and pinning a version.

## 1. API key and spend limit

In the [Anthropic Console](https://console.anthropic.com/):

1. Create a workspace for the bot, for example `review-bot`.
2. Set the workspace's **monthly spend limit**. This is the only hard cap on what the
   bot can spend; the optional ledger only paces spending. If you use the ledger, set
   the limit a little above
   [`monthly_budget_usd`](configuration.md#workflow-inputs).
3. Create an API key in that workspace.

Reviews call the Claude API directly, so any credit that covers API usage pays for them.

## 2. Add the bot to a repo

Set the key as a secret, then add a workflow file.

```bash
gh secret set ANTHROPIC_API_KEY --repo <owner>/<repo>   # prompts for the value
```

Choose one of the two workflow files and copy it to `.github/workflows/review-bot.yml`:

| File | Use it when |
|---|---|
| [`examples/caller.yml`](../examples/caller.yml) | Normally. It is a few lines long and calls this repo's reusable workflow, so you get changes without editing anything |
| [`examples/standalone.yml`](../examples/standalone.yml) | Your repo's CI must see every job's runner, for example a gate that refuses jobs from external reusable workflows. Everything is in the one file. It has no spend ledger |

Both pass `ANTHROPIC_API_KEY` by name. Keep it that way: `secrets: inherit` does not
pass secrets to a workflow owned by another account.

Reviews post as `github-actions[bot]` with the workflow's own token. No GitHub App is
needed.

### Many repos at once

For an organisation, set the secret once at organisation level and choose which repos
can use it:

```bash
gh secret set ANTHROPIC_API_KEY --org <org> --repos "repo-one,repo-two"
```

For several personal repos, [`scripts/install.sh`](../scripts/install.sh) sets the key
and the ledger token on each repo you name, so it needs both: without a
[ledger](#3-optional-a-shared-spend-ledger), run `gh secret set` per repo instead. It
reads both values from the environment, so they never appear on the command line:

```bash
read -rs ANTHROPIC_API_KEY; read -rs REVIEW_BOT_LEDGER_TOKEN
export ANTHROPIC_API_KEY REVIEW_BOT_LEDGER_TOKEN
scripts/install.sh <owner>/<repo> <owner>/<other-repo>
```

It sets secrets only; add the workflow file to each repo through its normal PR process.

## 3. Optional: a shared spend ledger

Without a ledger the bot always uses the normal tiers and the Console limit is the
only stop. With one, every repo adds its runs to one file, and the bot steps down
from councils to single reviews to none as the month's budget fills (the
[budget ladder](configuration.md#budget-ladder)).

1. Create a **secret gist** containing one file, `ledger.json`, with the content `{}`.
2. Create a **fine-grained personal access token** with only the *Gists: read and
   write* permission.
3. Add it to each repo as `REVIEW_BOT_LEDGER_TOKEN`.
4. In your caller file, pass the gist ID and the token:

   ```yaml
   uses: JackScammell/review-bot/.github/workflows/review.yml@v1
   with:
     budget_gist_id: <gist id>
   secrets:
     ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
     REVIEW_BOT_LEDGER_TOKEN: ${{ secrets.REVIEW_BOT_LEDGER_TOKEN }}
   ```

The ledger looks like this:

```json
{ "2026-11": { "spent": 12.34, "runs": [ { "repo": "owner/name", "pr": 7, "tier": "single", "cost": 0.09, "estimated": false, "at": "2026-11-10T12:00:00Z" } ] } }
```

Two runs finishing at the same moment can overwrite each other's entry, and anyone
holding the token can edit it. If the file stops being a JSON object of months, the bot treats the
ledger as unreadable (single reviews only) and does not overwrite it.

## Pinning a version

`@v1` is a moving tag: it is updated to the latest release, so every repo picks up
changes on its next run. For a fixed version, pin all three refs to commit SHAs:

```yaml
uses: JackScammell/review-bot/.github/workflows/review.yml@<commit sha>
with:
  bot_ref: <same commit sha>
  council_ref: <Parliament-Of-Chaos commit sha>
```

`bot_ref` decides which scripts and prompts run, and `council_ref` which reviewer
personas the council uses, so pin those too. See [SECURITY.md](../SECURITY.md) for why
this matters.

## Try it without spending anything

From a checkout of the PR's branch, with the `gh` CLI signed in:

```bash
git clone https://github.com/JackScammell/review-bot .review-bot
DRY_RUN=1 TIER=council PR=<number> REPO=<owner>/<repo> python3 .review-bot/scripts/review_bot.py
```

A dry run gathers the PR, picks the council and prints the start of what it would send.
It makes no API calls, posts nothing and needs no API key or Python packages.
