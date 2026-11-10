# How it works

A run has two jobs. **Plan** ([`scripts/plan.sh`](../scripts/plan.sh)) decides whether
to review and at which tier; it is quick and costs nothing. **Review**
([`scripts/review_bot.py`](../scripts/review_bot.py)) gathers the PR, calls the Claude
API and posts the result. The rules the plan job follows are in
[configuration.md](configuration.md).

## What the bot reads

For each review the bot builds one block of context:

- The PR's title, description and size. The description is marked as the author's
  text: material to review, never instructions.
- The repo's own rules from `.github/review-bot-rules.md`, read from the base branch.
- The bot's previous review on this PR, if any, and the diff of everything pushed
  since. Each review carries a hidden marker with the commit it reviewed and its round
  number, so a follow-up round checks the earlier findings rather than starting over.
- The full diff, cut at a size limit (the model is told when it is cut).
- The full new contents of the changed files, biggest change first, up to a limit per
  file and in all. Lockfiles, minified files and
  common binary files are skipped ([which ones](configuration.md#council-selection)).

The limits are in [configuration.md](configuration.md#context-and-output-limits).

## Single review

One call to the model with the house rules, the context and the
[single-review prompt](../prompts/single.md). The reply has to match a fixed JSON
shape: a verdict, a short summary, and a capped list of findings, each with a severity, file,
line, title and explanation. The model has no tools; it can only return that JSON.

## Council review

1. **Choose the members** from what the PR touches
   ([council selection](configuration.md#council-selection)). Security and code
   quality always sit.
2. **Each member reviews** with its persona from
   [Parliament of Chaos](https://github.com/JackScammell/Parliament-Of-Chaos/tree/main/agents)
   and the [member prompt](../prompts/council-member.md), in its own domain only. The
   first member runs alone so that the shared context is cached; the rest then run in
   parallel and read the cached copy, which costs much less than sending it fresh.
3. **The chair merges** the members' reports with the
   [synthesis prompt](../prompts/council-synthesis.md): duplicates combined, findings
   that are wrong or out of scope dropped, and the rest capped.

If a member fails, the council carries on without it and the review lists it as
failed. If every member fails, no review is posted.

## Posting

The bot posts **one PR review**, always as a comment: it never approves and never
requests changes, so it cannot block a merge. Findings on a line that is part of the
diff also appear as inline comments on that line. If GitHub rejects the inline
comments, the bot posts the review again without them. Any `@name` in the model's text
is broken up so the bot never tags anyone.

Verdicts follow the Parliament of Chaos scale:

| Verdict | Meaning |
|---|---|
| REJECT | At least one Critical or High finding |
| APPROVE-WITH-NOTES | Only Medium or Low findings |
| APPROVE | Nothing worth recording |
| NO-FINDINGS | A council member found nothing in its domain |

## Cost

The bot works out each run's cost from the token counts the API returns and its own
price table, and prints it in the review. Models it has no price for are counted at
the highest price in the table, so cost is never under-counted. With a ledger, the
cost is added to it. If a run reports no cost, a fixed
[estimate](configuration.md#context-and-output-limits) is recorded instead. That
includes a run that fails before it calls the API, so the ledger can over-count but
never under-counts.

In the first live runs, on an ordinary pull request, a single review cost about $0.09
and a council review about $0.16. Cost grows with the size of the PR and the number
of council members.

## Limits

- **Advisory only.** The bot reads text the PR author wrote. A PR can try to steer its
  verdict, so treat a review as a second pair of eyes, not a gate. See
  [SECURITY.md](../SECURITY.md).
- **Reviews on open and on request, not on every push.** Comment `/review` or
  `/council` after a round of fixes.
- **Large PRs are cut.** Beyond the limits above, the model sees part of the diff and
  some of the files.
- **The ledger paces, it doesn't cap.** Two runs finishing together can lose one
  entry. See [the spend limit](setup.md#1-api-key-and-spend-limit).
- **Fork PRs aren't reviewed automatically**, because GitHub gives workflows on fork
  PRs no secrets. A maintainer can comment `/review` instead.
- **Moving refs.** Callers on `@v1` and the council on Parliament-Of-Chaos `main`
  pick up changes automatically. [Pin a SHA](setup.md#pinning-a-version) to avoid that.
- **No end-to-end test in CI.** CI tests the decision logic and helpers without an
  API key; a live review is checked by hand on a test PR.
