---
name: sentry
description: sentry
---

# sentry

## When to Use

- Whenever the user asks you about Sentry issues or errors.

## Instructions

Use the sentry CLI. Use `sentry --version` if a command fails because the executable couldn't be found. If it's not installed tell the user. Use `sentry auth status` if a command fails due to lack of authentication. Prompt the user to authenticate if it's not authenticated.

Never run commands that would change data in Sentry. Tell the user if running one of those commands would help with their request but don't run  it.

Builds may be refered to in this format: `issues/7377080149` or `7377080149`. These both mean the issue id is `7377080149`.
