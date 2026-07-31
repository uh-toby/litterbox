---
name: pr-review
description: Collaboratively review a pull request — pull the full PR context, run an independent critical review of the diff, triage existing reviewer comments, and deliver a reasoned assessment. Trigger when the user asks to review a PR, work through PR feedback, or wants a second opinion on a change before merging. Read-only by default; can make targeted local code changes on request, but never pushes or posts.
---

# Reviewing a pull request

Review a PR *with* the user, not for them. The output is a reasoned assessment they can act on — not an auto-applied set of fixes.

This skill is **read-only against GitHub**. It never pushes, never posts comments, never approves or requests changes. It may make targeted code changes **locally** when the user explicitly asks, but the user owns everything that touches the PR.

All GitHub access (fetching the PR, diff, comments, threads, CI status) goes through the **github skill** — read `skills/github/SKILL.md` and use `gh` as described there. Do not encode `gh` invocations here; defer to that skill for command shapes, pagination, and JSON filtering.

## 1. Choose the review mode

Before doing anything else, ask the user what kind of review they want. Present three options plainly and wait for an answer:

- **Comment triage** — only work through the existing reviewer comments on the PR. Skips the independent critical review (step 4).
- **Code review** — only do an independent adversarial pass over the diff. Skips the existing-comment triage (step 5).
- **Both** — the full flow: independent review *and* comment triage.

If the user already made their intent clear in their request (e.g. "help me work through the review feedback" → comment triage; "is this change sound?" → code review), infer the mode and confirm it in one line rather than asking redundantly.

The chosen mode governs which of the later steps run and what the synthesis (step 6) presents. Steps below that depend on the mode are marked accordingly.

## 2. Identify the PR

- If the user gave a PR number or a `github.com/...` URL, use it.
- Otherwise resolve the PR for the current branch.

Use the github skill for the mechanics.

## 3. Gather context

Pull enough to review the change on its own terms. Via the github skill, fetch:

- **PR metadata** — title, description, author, state, review decision, mergeability
- **The diff** — the actual change, plus changed-file list
- **Existing review comments and threads** — inline comments and top-level review summaries, from all reviewers (human and bot alike), noting which threads are resolved vs. unresolved
- **CI / checks status** — surface failing checks
- **Surrounding code** — when the diff touches code whose correctness depends on context not shown in the diff, read the relevant files locally (or via the github skill if not checked out) before forming an opinion

Don't paste raw diff or raw comment dumps back to the user — read it, then synthesize.

In **comment triage** mode you can skip fetching the full diff if it isn't needed to reason about the comments — but you'll usually still want the surrounding code to form a take.

## 4. Run your own critical review

*(Skip this step in **comment triage** mode.)*

Independently of what other reviewers said, do a genuinely adversarial pass over the diff. Be skeptical: assume there is a bug or a gap and try to find it. Use your full judgment as a reviewer — don't work from a fixed checklist.

For each thing you find:

- Cite the specific **file:line**
- State the concern plainly and *why* it matters
- Rate severity: **blocker** / **should-fix** / **nit** / **question**
- Where useful, suggest a concrete direction (not necessarily a full patch)

If the change looks genuinely clean, say so — don't manufacture findings.

## 5. Triage the existing reviewer comments

*(Skip this step in **code review** mode.)*

For each existing comment on the PR, form a reasoned take: do you agree, disagree, or is it underspecified? Explain your reasoning, with code context. Treat human and bot comments the same way — this is not specific to any one reviewer.

## 6. Synthesize

Present the assessment in the buckets relevant to the chosen mode. Where both buckets apply, keep them clearly separated — the distinction matters.

### PR comments (require user action regardless)

*(Present in **comment triage** and **both** modes.)*

Comments left on the PR by reviewers. These need a response **on the PR** — a reply or a resolution — whether or not we agree with them, because another party is waiting on them. For each:

- Who left it, file:line, what they said
- Your reasoned take (agree / disagree / needs-info, and why)
- Suggested response or resolution for the user to act on

We do **not** post these. The user replies. When drafting a reply body for them, note the backtick gotcha (see below).

### Agent findings (for the user to consider locally)

*(Present in **code review** and **both** modes.)*

Your own review findings from step 4. These carry **no external obligation** — there's no thread waiting on them. They're for the user to weigh and decide whether to act on. For each: file:line, severity, the concern, and a suggested direction.

In **both** mode, keep the two buckets visually and conceptually separate so the user always knows what needs a PR action vs. what's just our advice.

## 7. Work through it together

Walk the user through the assessment collaboratively. Let them drive which items to dig into.

If the user asks you to make a change, make it **locally** in the relevant file, scoped tightly to the item discussed, and confirm before moving on. Do not commit unless asked, and never push.

## Posting replies is out of scope

This skill does not post to GitHub. If the user wants to reply to a comment (human or bot) or post a resolution, that is a mutation outside this skill and the read-only github skill — the user runs it, or explicitly confirms before any write.

When you draft a reply body for the user: **never** embed it inline in a shell command — backticks get mangled by shell substitution and break code spans. Write the body to a file first and have the user pass it with `--body-file`.