#!/usr/bin/env bash
# Sets the two review-bot secrets on each repo given.
# Adding the caller workflow file is left to each repo's normal PR process.
#   ANTHROPIC_API_KEY=... REVIEW_BOT_LEDGER_TOKEN=... scripts/install.sh owner/repo [owner/repo ...]
# For an organisation, prefer one org-level secret instead:
#   gh secret set ANTHROPIC_API_KEY --org my-org --repos "repo1,repo2"
set -euo pipefail
: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY}" "${REVIEW_BOT_LEDGER_TOKEN:?set REVIEW_BOT_LEDGER_TOKEN}"

for repo in "$@"; do
  echo "== $repo"
  printf '%s' "$ANTHROPIC_API_KEY" | gh secret set ANTHROPIC_API_KEY --repo "$repo"
  printf '%s' "$REVIEW_BOT_LEDGER_TOKEN" | gh secret set REVIEW_BOT_LEDGER_TOKEN --repo "$repo"
done
