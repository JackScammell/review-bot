#!/usr/bin/env bash
# Builds the review prompt: shared rules + tier prompt + the repo's own rules
# file (.github/review-bot-rules.md in the reviewed repo, if present).
set -euo pipefail
BOT=.review-bot/prompts

{
  sed -e "s/{{PR}}/$PR/g" -e "s#{{REPO}}#$REPO#g" "$BOT/$TIER.md"
  echo
  cat "$BOT/house-rules.md"
  if [ -f .github/review-bot-rules.md ]; then
    echo
    echo "## Rules for this repository"
    cat .github/review-bot-rules.md
  fi
} > /tmp/review-prompt.md

DELIM="PROMPT_$(openssl rand -hex 8)"
{
  echo "prompt<<$DELIM"
  cat /tmp/review-prompt.md
  echo "$DELIM"
} >> "$GITHUB_OUTPUT"
