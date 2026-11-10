#!/usr/bin/env bash
# Shared ledger helpers. The ledger is ledger.json in one gist:
#   { "2026-11": { "spent": 12.34, "runs": [ {repo, pr, tier, cost, estimated, at} ] } }
# Needs LEDGER_TOKEN and GIST_ID.

ledger_read() {
  local content
  content=$(GH_TOKEN="$LEDGER_TOKEN" gh api "gists/$GIST_ID" --jq '.files["ledger.json"].content' 2>/dev/null) || return 1
  if [ -z "$content" ] || ! echo "$content" | jq -e . >/dev/null 2>&1; then
    echo '{}'
  else
    echo "$content"
  fi
}

ledger_write() {
  # $1 = full ledger JSON
  jq -n --arg c "$1" '{files: {"ledger.json": {content: $c}}}' |
    GH_TOKEN="$LEDGER_TOKEN" gh api -X PATCH "gists/$GIST_ID" --input - >/dev/null
}

month_key() { date -u +%Y-%m; }
