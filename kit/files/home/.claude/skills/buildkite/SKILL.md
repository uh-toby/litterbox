---
name: buildkite
description: buildkite
---

# buildkite

## When to Use

- Whenever the user asks you about Buildkite builds, pipelines, and jobs.

## Instructions

Use the bk CLI. Use `bk --version` if a command fails because the executable couldn't be found. If it's not installed tell the user. Use `bk auth status` if a command fails due to lack of authentication. Prompt the user to authenticate if it's not authenticated.

Never run commands that would change data in Buildkite, eg `write_...`, `delete_...`. Tell the user if running one of those commands would help with their request but don't run  it.

Builds may be refered to in this format: `usabilityhub/mobile-build/builds/1447`. This means the organization is `usabilityhub`, the pipeline is `mobile-build` and the build number is `1447`.
