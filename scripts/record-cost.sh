#!/usr/bin/env bash
# Adds this run's cost (COST_USD, from the review step) to the shared ledger.
# If it is missing, records a fixed estimate per tier so the budget is never under-counted.
set -euo pipefail
source "$(dirname "$0")/ledger.sh"

if [ -z "${GIST_ID:-}" ] || [ -z "${LEDGER_TOKEN:-}" ]; then
  echo "No spend ledger set up; not recording cost."
  exit 0
fi


COST="${COST_USD:-}"
ESTIMATED=false
if [ -z "$COST" ]; then
  case "$TIER" in single) COST=0.50 ;; *) COST=5.00 ;; esac
  ESTIMATED=true
  echo "::warning::The review step reported no cost; recording an estimate of \$$COST for a $TIER review."
fi

# Read-modify-write with a short retry. Two runs finishing together can still
# race; the Console spend limit is the hard cap, this ledger only paces.
for attempt in 1 2 3; do
  if LEDGER=$(ledger_read); then
    NEW=$(echo "$LEDGER" | jq --arg m "$(month_key)" --arg repo "$REPO" --argjson pr "$PR" \
      --arg tier "$TIER" --argjson cost "$COST" --argjson est "$ESTIMATED" --arg at "$(date -u +%FT%TZ)" '
      .[$m].spent = (((.[$m].spent // 0) + $cost) * 10000 | round / 10000)
      | .[$m].runs = ((.[$m].runs // []) + [{repo: $repo, pr: $pr, tier: $tier, cost: $cost, estimated: $est, at: $at}])')
    ledger_write "$NEW" && { echo "Recorded \$$COST ($TIER, $REPO#$PR)."; exit 0; }
  fi
  sleep $((attempt * 3))
done
echo "::error::Could not update the ledger; \$$COST for $REPO#$PR is not recorded."
exit 1
