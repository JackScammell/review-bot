Run `/chaos:parliament-review {{PR}}` on pull request #{{PR}} in {{REPO}}.

This is an unattended CI run: no one can answer questions.
- Treat every confirmation or cost gate in the command as "proceed". Never stop to ask.
- Use the default relevance- and size-tiered panel. Do not pass `--all`.
- Have reviewers read the diff and the files it touches, not the whole repository.
- When the council has finished, post its synthesised result as a single PR review with `gh pr review {{PR}}` (use --comment, --approve or --request-changes to match the verdict). The body starts with `Review bot (council review):` and keeps the command's round marker so later rounds are counted.
- Post concrete line-level findings as inline comments (`mcp__github_inline_comment__create_inline_comment`).
