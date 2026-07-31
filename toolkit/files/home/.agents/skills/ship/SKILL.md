---
name: ship
description: Push the current branch and create a draft pull request with gh
disable-model-invocation: true
---

# Ship — push branch and create a draft PR

## Step 1: Pre-flight checks

1. Run `git status` — If there is work that still needs to be committed, commit it. Warn if there is anything unexpected.
2. Run `git log --oneline origin/main..HEAD` to see what commits will be in the PR

## Step 2: Push the branch

```
git push -u origin HEAD
```

## Step 3: Create the draft PR

1. Derive the PR title from the branch name and commit messages
2. Prefix the PR title with the linear ticket in brackets, like `[RES-123] `
3. Look at the commit messages to write a concise PR body
4. If the branch name starts with a ticket ID (e.g., `res-123-`), include a link to the Linear ticket in the PR body

```
gh pr create --draft --title "<title>" --body "<body>"
```

Use a HEREDOC for the body to preserve formatting:
```
gh pr create --draft --title "<title>" --body "$(cat <<'EOF'
## Summary
<explanation or bullet points>

## Linear
<link to ticket if applicable>

## Test plan
<how to test>
EOF
)"
```

5. Request an initial review from Github Copilot

```
gh pr edit --add-reviewer @copilot
```

6. Output the PR URL so the user can open it