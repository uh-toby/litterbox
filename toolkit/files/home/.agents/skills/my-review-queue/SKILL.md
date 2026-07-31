---
name: my-review-queue
description: Summarize the open PRs specifically assigned to the current user for review on GitHub, including the CI check status of each. Use when the user asks to see, list, or summarize PRs assigned to them for review.
---

# My Review Queue

Summarizes the open pull requests specifically assigned to the current user for review, including the status of their CI checks.

## When to use

- The user asks "what PRs are assigned to me for review", "summarize my review queue", or similar.
- The user wants to triage their pending reviews.

## Why assignee, not review-requested

Always use the **assignee** query (`assignee:@me`). Someone deliberately assigned these PRs to the user — this is the narrow, "specifically mine" list. It excludes review requests made via CODEOWNERS / team membership, which are noisy and not specifically the user's responsibility.

Do **not** use `review-requested:@me` — that pulls in every CODEOWNERS/team request.

## Command

The `statusCheckRollup` field returns every check for each PR in a single call:

```bash
gh pr list --search "assignee:@me state:open" \
  --json number,title,author,url,updatedAt,additions,deletions,isDraft,statusCheckRollup --limit 100
```

Each `statusCheckRollup` entry has `status`/`conclusion` (for check runs) or `state` (for legacy statuses). Summarize per PR by counting outcomes — e.g. passed / failed / pending / skipped. Treat `conclusion` of `SUCCESS`/`NEUTRAL`/`SKIPPED` as passing, `FAILURE`/`TIMED_OUT`/`CANCELLED`/`ACTION_REQUIRED` as failing, and anything still `IN_PROGRESS`/`QUEUED`/`PENDING` (or empty conclusion) as pending.

## Presenting results

- Group **human-authored** PRs separately from **bot-authored** ones (`author.is_bot === true`, e.g. `wearelyssna-bot`, `cursor`). The human PRs are the real review priority; bot `[package-update]` bumps are usually a batch triage.
- Where a set of PRs shares a ticket prefix (e.g. `PLA-934`, `PLA-894`), group them together.
- Render as a Markdown table. The PR column must be a clickable https link using the `url` field: `[#28446](https://github.com/wearelyssna/hub/pull/28446)`.
- Include size (`+additions/−deletions`), last-updated date, and a **Checks** column.
- The Checks column must always be present. Show a rollup like `✅ 12/12`, `❌ 2 failing`, or `⏳ 3 pending` (e.g. `✅ 10 · ❌ 1 · ⏳ 2`). If a PR has no checks, say `—`.
- Flag **drafts** (`isDraft: true`) — they're usually not review-ready.
- Call out anything unusual: a huge diff (likely vendored/generated), a PR stale for weeks, or failing checks.

## Follow-ups to offer

- Show the failing check details for a specific PR (`gh pr checks <number>`).
- Run a full review on one (`/pr-review`).
- Batch-triage the bot package-update PRs.