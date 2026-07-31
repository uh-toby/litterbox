---
name: linear
description: linear
---

# linear

## When to Use

- Whenever the user asks you about Linear issues or "cards".


## Instructions

Use the linear CLI. Use `linear --version` if a command fails because the executable couldn't be found. If it's not installed tell the user. Use `linear auth whoami` if a command fails due to lack of authentication. Prompt the user to authenticate if it's not authenticated.

Always ask the user before running commands that would change data in Linear.

## Finding issues assigned to a user

`--assignee` matches its argument as a substring against user names/emails - it is **not** a "current user" keyword. Passing `--assignee me` does NOT mean "the authenticated user"; it literally matches any name containing "me". Always pass a unique identifier, and prefer the email over a short username so it can't collide: `linear issue query --assignee <email> --all-teams`.

Use `linear issue query ... --all-teams`, not `linear issue mine`, to list a user's issues across every team. `linear issue mine` (and unscoped `query`) requires a default team and fails with "No default team configured" — do not try to fix that by running `linear config` (see above); pass `--all-teams` instead. Default team scope only limits which team a command looks at; it has nothing to do with which issues a user is assigned.

Add state filters for open work (omit for everything):

  linear issue query --assignee <email> --all-teams \
    -s triage -s backlog -s unstarted -s started
