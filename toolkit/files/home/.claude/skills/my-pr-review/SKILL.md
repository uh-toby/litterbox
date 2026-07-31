---
name: my-pr-review
description: Collaboratively review a pull request — pull the full PR context, run an independent critical review of the diff, triage existing reviewer comments, and deliver a reasoned assessment. Read-only by default; can make targeted code changes on request.
argument-hint: [pr-number (optional, defaults to current branch PR)]
---

# Reviewing a pull request

Review a PR *with* the user, not for them. The output is a reasoned assessment they can act on — not an auto-applied set of fixes.

## 1. Find the PR

If a PR number/URL was given, use it: **$ARGUMENTS**.

Otherwise resolve for the current branch:
```
gh pr view --json number,title,url
```

## 2. Build context

Fetch what's needed to reason about the change. Don't paste raw dumps back to the user — synthesize instead.

- **Metadata**: title, description, author, review decision, mergeability
- **Diff**: changed files and the actual change
- **Comments & threads**: `gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate` plus `gh pr view {number} --json reviewDecision,reviews,comments`; note resolved vs unresolved
- **Checks**: `gh pr checks {number}`
- **Surrounding code**: read files locally when the diff's correctness depends on context outside the diff

## 3. Checks

- `gh pr checks {number}` for current status
- For each failing check, pull the logs (`gh run view <run-id> --log-failed` for GitHub Actions; hand off to the **buildkite** skill's `bk` CLI for Buildkite builds)
- Diagnose the root cause and suggest a concrete fix — don't apply it unless asked
- Call out flaky/infra failures separately from failures the diff actually caused

## 4. Run your own critical review

Independently of what other reviewers said, do a genuinely adversarial pass over the diff. Be skeptical: assume there is a bug or a gap and try to find it. Use your full judgment as a reviewer — don't work from a fixed checklist.

For each thing you find:

- Cite the specific **file:line**
- State the concern plainly and *why* it matters
- Rate severity: **blocker** / **should-fix** / **nit** / **question**
- Where useful, suggest a concrete direction (not necessarily a full patch)

If the change looks genuinely clean, say so — don't manufacture findings.

## 5. Comment triage

For each unresolved comment:
1. Show the comment: who said it, what file/line, and what they said
2. Show the relevant code context
3. Give a recommendation about how to proceed
4. Ask the user to confirm before making any changes

## 6: Make changes

When addressing comments:
- Make the fix in the relevant file
- If the user wants to fold changes into existing commits to keep history clean, use interactive rebase:
  - `git stash` any uncommitted changes first if needed
  - Amend the relevant commit with `git commit --fixup=<sha>` then `git rebase -i --autosquash origin/main`
  - Or amend the last commit directly with `git commit --amend` if appropriate
- If a new commit is more appropriate, create one with a clear message
- After each change, confirm with the user before moving to the next comment

## 7: Push updates

After all comments are addressed:
```
git push --force-with-lease
```

Use `--force-with-lease` (not `--force`) to safely push rewritten history.

## 8: Reply to comments

For Copilot comments, reply to each with our resolution or with our reasoning for not fixing, if we decide not to do it. Leave human comments for the human author to reply to.

### Posting replies without mangling backticks

**Never** pass reply bodies inline via `--body "..."` — bash command substitution eats backticks and breaks code spans/blocks. Always write the body to a file first and pass it with `--body-file`.

Reply to a specific review comment (threads it under the original):
```
# Write the body with the Write tool to /tmp/reply.md, then:
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  --method POST \
  --field body=@/tmp/reply.md
```

Or for a top-level PR comment:
```
gh pr comment {pr} --body-file /tmp/reply.md
```

Use the Write tool (not `cat <<EOF` heredocs in bash) to author the file — Write preserves backticks exactly as typed with zero shell interpretation.