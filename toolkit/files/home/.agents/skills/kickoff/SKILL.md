---
name: kickoff
description: Start new work from a Linear ticket — pull ticket info, agree on scope, create a worktree branch
disable-model-invocation: true
argument-hint: [ticket-id e.g. RES-532]
---

# Kickoff new work from a Linear ticket

## Step 1: Understand the ticket

Get the Linear issue for **$ARGUMENTS**:
- Use the Linear CLI `linear issue view` tool to fetch the full ticket details
- Summarize: title, description, acceptance criteria, and any comments
- Note the ticket ID and title — you'll need them for the branch name
- If the Linear issue is not already in "Doing" status, update it to "Doing" (not "In Progress", that doesn't exist)
- If there are related resources in the ticket like Figma designs, explore those to build out your understanding.

## Step 2: Scope the work

Before writing any code:
- Present your understanding of what needs to be done
- Ask clarifying questions — what's in scope, what's out, risks, unknowns
- Propose a high-level approach
- **Wait for the user to confirm scope before proceeding**

## Step 3: Start the work

1. Fetch latest main:
   ```
   git fetch origin main
   ```

2. Derive the branch name:
   - Format: `{ticket-id-lowercase}-{slugified-title}` (e.g., `res-123-update-some-code`)
   - Keep it short and readable — truncate the title slug if needed
   - If the Linear suggested branch name is long (they often are) feel free to use a more compact one

3. If the user wants to work in a worktree, create the worktree off `origin/main`:
   ```
   git worktree add -b <branch-name> .claude/worktrees/<branch-name> origin/main
   ```

4. After the plan is confirmed, begin development work.