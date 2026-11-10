#!/usr/bin/env bash
# Shared ledger helpers. The ledger is ledger.json in one gist:
#   { "2026-11": { "spent": 12.34, "runs": [ {repo, pr, tier, cost, estimated, at} ] } }
# Needs LEDGER_TOKEN and GIST_ID.

# ledger_read returns 1 if the gist can't be fetched and 2 if ledger.json is damaged.
ledger_read() {
  local content
  content=$(GH_TOKEN="$LEDGER_TOKEN" gh api "gists/$GIST_ID" --jq '.files["ledger.json"].content' 2>/dev/null) || return 1
  # An empty file is a fresh ledger. Anything else that isn't a JSON object counts as
  # unreadable, so plan.sh falls back to single reviews and record-cost.sh never
  # overwrites a damaged ledger with a fresh one.
  if [ -z "$content" ] || [ "$content" = null ]; then
    echo '{}'
  elif echo "$content" | jq -e 'type == "object" and all(.[]; type == "object"
      and (.spent // 0 | type == "number") and (.runs // [] | type == "array"))' >/dev/null 2>&1; then
    echo "$content"
  else
    echo "::warning::ledger.json is not a JSON object of months; treating the ledger as unreadable." >&2
    return 2
  fi
}

ledger_write() {
  # $1 = full ledger JSON
  jq -n --arg c "$1" '{files: {"ledger.json": {content: $c}}}' |
    GH_TOKEN="$LEDGER_TOKEN" gh api -X PATCH "gists/$GIST_ID" --input - >/dev/null
}

month_key() { date -u +%Y-%m; }
