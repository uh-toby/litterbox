---
name: pr-comments
description: Fetch unresolved PR review comments and triage them together
disable-model-invocation: true
argument-hint: [pr-number (optional, defaults to current branch PR)]
---

# Review PR comments

## Step 1: Find the PR

If a PR number was provided, use it: **$ARGUMENTS**

Otherwise, detect the PR for the current branch:
```
gh pr view --json number,title,url
```

## Step 2: Fetch unresolved comments

Get all review comments:
```
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
```

Also get review threads to identify which are resolved:
```
gh pr view {number} --json reviewDecision,reviews,comments
```

Filter to **unresolved** comments only.

## Step 3: Triage together

For each unresolved comment:
1. Show the comment: who said it, what file/line, and what they said
2. Show the relevant code context
3. Give a recommendation about how to proceed
3. Ask the user to confirm before making any changes

## Step 4: Make changes

When addressing comments:
- Make the fix in the relevant file
- If the user wants to fold changes into existing commits to keep history clean, use interactive rebase:
  - `git stash` any uncommitted changes first if needed
  - Amend the relevant commit with `git commit --fixup=<sha>` then `git rebase -i --autosquash origin/main`
  - Or amend the last commit directly with `git commit --amend` if appropriate
- If a new commit is more appropriate, create one with a clear message
- After each change, confirm with the user before moving to the next comment

## Step 5: Push updates

After all comments are addressed:
```
git push --force-with-lease
```

Use `--force-with-lease` (not `--force`) to safely push rewritten history.

## Step 6: Reply to comments

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