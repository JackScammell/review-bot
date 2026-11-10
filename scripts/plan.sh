#!/usr/bin/env bash
# Decides whether to review, and at which tier, from the event, the PR's size
# and risk, and this month's spend in the shared ledger.
# Writes tier (none | single | council | budget-hold), pr and reason to $GITHUB_OUTPUT.
set -euo pipefail
source "$(dirname "$0")/ledger.sh"

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; echo "$1=$2"; }
finish() { out tier "$1"; out pr "${PR:-0}"; out reason "$2"; exit 0; }

ev() { jq -r "$1" "$EVENT_PATH"; }

PR=""
REQUESTED=""   # single | council when a person asked for it
case "$EVENT_NAME" in
  pull_request|pull_request_target)
    PR=$(ev '.pull_request.number')
    [ "$(ev '.pull_request.draft')" = "true" ] && finish none "Draft PR."
    ;;
  issue_comment)
    [ "$(ev '.issue.pull_request // empty')" = "" ] && finish none "Comment is not on a PR."
    PR=$(ev '.issue.number')
    case "$(ev '.comment.author_association')" in
      OWNER|MEMBER|COLLABORATOR) ;;
      *) finish none "Commenter has no write access." ;;
    esac
    BODY=$(ev '.comment.body' | head -n1 | tr -d '\r')
    case "$BODY" in
      /council*) REQUESTED=council ;;
      /review*)  REQUESTED=single ;;
      *) finish none "Not a review-bot command." ;;
    esac
    ;;
  *) finish none "Unsupported event $EVENT_NAME." ;;
esac

# --- Size and risk (lockfiles and generated files excluded) -------------------
FILES=$(gh pr view "$PR" --repo "$REPO" --json files --jq '.files')
LOCK_RE='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|composer\.lock|packages\.lock\.json|Cargo\.lock|poetry\.lock|[^/]*\.min\.(js|css))$|(^|/)dist/'
LINES=$(echo "$FILES" | jq --arg re "$LOCK_RE" '[.[] | select(.path | test($re) | not) | .additions + .deletions] | add // 0')
RISK_RE='\.sql$|(^|/)migrations?/|auth|login|password|permission|secret|token|\.github/workflows/|Dockerfile|appsettings|\.env'
RISKY=$(echo "$FILES" | jq -r --arg re "$RISK_RE" '[.[] | select(.path | test($re; "i")) | .path] | first // ""')

if [ -n "$REQUESTED" ]; then
  WANT=$REQUESTED; WHY="asked for $REQUESTED"
elif [ "$LINES" -gt "$LARGE_PR_LINES" ]; then
  WANT=council; WHY="large PR ($LINES lines)"
elif [ -n "$RISKY" ]; then
  WANT=council; WHY="touches a risky path ($RISKY)"
else
  WANT=single; WHY="small or low-risk PR ($LINES lines)"
fi

# --- Budget ladder ------------------------------------------------------------
if [ -z "${GIST_ID:-}" ] || [ -z "${LEDGER_TOKEN:-}" ]; then
  # No ledger configured: normal tiers; the Console spend limit is the only stop.
  finish "$WANT" "$WHY; no spend ledger set up, so the Console limit is the only cap."
fi
if ! LEDGER=$(ledger_read); then
  # Ledger unreadable: allow only the cheap tier. The Console cap is the backstop.
  finish single "Ledger unreadable, so single review only; $WHY."
fi
SPENT=$(echo "$LEDGER" | jq --arg m "$(month_key)" '.[$m].spent // 0')

# PCT = share of budget spent; PACE = spent / share of the month gone (>1 = ahead of pace).
read -r PCT PACE < <(awk -v s="$SPENT" -v b="$BUDGET" \
  -v y="$(date -u +%Y)" -v m="$(date -u +%m)" -v d="$(date -u +%d)" -v h="$(date -u +%H)" '
  BEGIN {
    split("31 28 31 30 31 30 31 31 30 31 30 31", len, " "); n = len[m + 0]
    if (m + 0 == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) n = 29
    f = ((d - 1) + h / 24) / n; if (f < 0.1) f = 0.1
    printf "%.3f %.3f\n", s / b, s / (b * f)
  }')
STATE="spent \$$SPENT of \$$BUDGET this month"

ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }

if ge "$PCT" 0.95; then
  finish budget-hold "$STATE."
elif ge "$PCT" 0.85; then
  [ "$WANT" = council ] && WHY="$WHY, reduced to a single review (85%+ of budget used)"
  WANT=single
elif ge "$PCT" 0.60 || ge "$PACE" 1.25; then
  if [ "$WANT" = council ] && [ "$REQUESTED" != council ]; then
    WANT=single; WHY="$WHY, but councils now run only on request (budget over 60% or ahead of pace)"
  fi
fi

finish "$WANT" "$WHY; $STATE."
