# toolkit

An `sbx` kit (mixin) that configures the prebuilt **pi**, **sentry**, **linear**, **gh** and **bk** tooling inside a sandbox, and includes a mirror of your host skills.

The static CLI installations live in an agent-specific Docker image; this kit contains the flexible runtime policy, egress, pi defaults, and skills. The only host-side step is storing the Sentry, Linear, Buildkite, and OpenRouter secrets; GitHub needs nothing, see below. OpenRouter is supplied by sbx's built-in shell-agent credential rather than declared by this kit, avoiding a credential collision when the kit is composed with `shell`.

Authored against kit-spec **v2**, validated on sbx `v0.35.0`.

## What it does

| Concern | How |
| --- | --- |
| CLIs | The matching prebuilt image installs pi 0.82.1 via npm and provides `sentry` 0.38.0, `linear` 2.3.0, `gh` 2.96.0 and `bk` 3.44.1 in `/usr/local/bin` |
| Pi | `pi` defaults to the OpenRouter model `openai/gpt-5.6-luna` |
| Pi auth | The shell agent's built-in OpenRouter credential injects the host-managed key for requests to `openrouter.ai` |
| Skills | `files/home/.claude/skills/` is a straight mirror of `~/.agents/skills/` → `/home/agent/.claude/skills/` |
| Egress | `caps.network.allow` opens the API hosts plus the release-download hosts |
| Auth | The proxy injects `Authorization` on requests to those API hosts; OpenRouter uses the shell agent's built-in credential |
| Secrecy | The Sentry, Linear, Buildkite, and OpenRouter tokens are `proxyManaged` — the container only sees `proxy-managed`. `GH_TOKEN` is the real token (gh shells out to git) |
| Discovery | The skills are auto-discovered by Claude Code, so the agent knows the integrations exist without being told |

## Configure the secrets

Two steps, both required. The kit is inert without them.

### 1. Store a *service* secret per service name

```sh
# OpenRouter — https://openrouter.ai/keys
# The shell agent declares this credential; the kit only opens its egress.
echo "$OPENROUTER_API_KEY" | sbx secret set -g openrouter

# Sentry — https://sentry.io/settings/account/api/auth-tokens/
echo "$SENTRY_AUTH_TOKEN" | sbx secret set -g sentry

# Linear — https://linear.app/settings/api
echo "$LINEAR_API_KEY" | sbx secret set -g linear

# Buildkite — https://buildkite.com/user/api-access-tokens
# Needs the read_* scopes (the skill forbids writes) and, for `bk` commands that
# use the GraphQL API, "Enable GraphQL API access" on the token.
echo "$BUILDKITE_API_TOKEN" | sbx secret set -g buildkite
```

These must be **service** secrets (`sbx secret set`), not **custom** secrets (`sbx secret set-custom`). `credentials[].service` binds to the service name; a custom secret is keyed by host+env and is a parallel mechanism. If both exist, the kit's `proxyManaged` env var wins and the custom secret is silently shadowed — the CLI sees `proxy-managed` and gets a 4xx. Check which kind you have with `sbx secret ls`; custom ones appear under a separate `CUSTOM SECRETS` heading and are removed with `sbx secret rm -g --placeholder <placeholder>`.

> `sbx secret set --help` only advertises its built-in services, but arbitrary service names are accepted. Verified on v0.35.0.

### 2. Authorize the credential with a binding

Needed for Sentry and Linear. **Buildkite turned out not to need one** — see [Buildkite](#buildkite) — but the create-time note claiming otherwise is emitted anyway, so read that section before acting on it.

A stored secret is not enough. sbx additionally requires a *binding* authorizing each service, or it skips injection and prints:

```
Note: no binding authorizes buildkite, linear, sentry — the credential was not injected.
Create a binding (re-run interactively, or edit ~/.config/sbx/credentials.yaml) to use it.
```

Create the sandbox **interactively** and approve the prompt — it offers to apply to all sandboxes, current and future, so it's a one-time step:

```sh
sbx run claude --template docker.io/toby/litterbox:claude-v1 --kit ~/projects/litterbox/toolkit .
```

This is a deliberate security gate, so approve it yourself rather than hand-forging `~/.config/sbx/credentials.yaml`. `.sbxenv.yaml` also has a `bindings:` key if you want it declared.

## Use it

```sh
sbx run shell --template docker.io/toby/litterbox:shell-v1 --kit ~/projects/litterbox/toolkit .
```

Inside the sandbox, run `pi`. It uses OpenRouter and `openai/gpt-5.6-luna` by default.

For an agent sandbox, use the image built from that agent's matching base:

```sh
sbx run claude --template docker.io/toby/litterbox:claude-v1 --kit ~/projects/litterbox/toolkit .
```

To avoid passing `--kit` every time, declare it in a `.sbxenv.yaml` (its schema includes `agent`, `kits`, `workspace`, `secrets`, `bindings`, `environment`, `ports`) and use `sbx env run`, which auto-discovers the file from the current directory. There is no global default-kit setting — I checked `sbx settings list`.

## Pi notes

Pi is installed globally in the matching agent image from npm at version 0.82.1. Its configuration is seeded at
`/home/agent/.pi/agent/settings.json`, with OpenRouter and
`openai/gpt-5.6-luna` as the defaults. The OpenRouter key is supplied by sbx's built-in shell-agent credential, so it
is never written into the kit or sandbox filesystem.

The kit has been validated with `sbx kit validate`. A new sandbox must be
created with the matching image to receive the seeded pi configuration.

## What was verified

Confirmed in real sandboxes, on both the `shell` and `claude` agents:

- The image provides all four CLIs: `sentry` `0.38.0`, `linear` `2.3.0`, `gh` `2.96.0`, `bk` `3.44.1` (at `/usr/local/bin/bk`). The image build retains the `xz-utils` fallback for slim base images.
- Skills land at `/home/agent/.claude/skills/{sentry,linear,github,buildkite}/`.
- Env is as intended: `SENTRY_AUTH_TOKEN=proxy-managed`, `LINEAR_API_KEY=proxy-managed`, `BUILDKITE_API_TOKEN=proxy-managed`, `SENTRY_FORCE_ENV_TOKEN=1`, `BUILDKITE_ORGANIZATION_SLUG=usabilityhub`.
- `DENO_CERT` resolves the linear CLI's TLS failure — with it, requests reach `api.linear.app` and fail only on authentication.
- Neither CLI validates token format locally, so the placeholder passes through to the proxy as designed.

**Authenticated calls succeed end-to-end**, with service secrets stored and bindings approved:

- `sentry auth whoami` → the correct identity; `sentry org list` → the real `lyssna` org.
- `linear team list` → the real team list.
- The proxy **replaces** the `Authorization` header the CLI already sent rather than appending a second one. This was the last open risk and it is now settled — no duplicate-header failure.
- `gh auth status` → logged in as the real account; `gh api user` and `gh pr list` return real data.
- Egress boundary holds: `sentry.io` → 200, `example.com` → 403.
- **A cold agent needs no sandbox-specific guidance.** With only the mirrored host skills and no `agentContext`, `claude -p` inside the sandbox found the right skill, used the CLI correctly and returned real data for both Linear (3 issues assigned to the right person) and Sentry (org `lyssna`, plus 2 unresolved issues).
- Both CLIs self-report as authenticated, which is why that works: `linear auth whoami` returns the real workspace and user, and `sentry auth status` prints `✓ Authenticated via SENTRY_AUTH_TOKEN`. The host skills' "prompt the user to authenticate" branch is simply never taken.

### Buildkite

Verified end-to-end in sandbox `bk-kit-test` (`shell` agent) on 2026-07-30: `bk auth status` returns the real token (`"description": "sbx access"`, the right user, `expires_at` 2026-10-28), and `bk build list` returns real builds. A direct `POST https://graphql.buildkite.com/v1` with `{ viewer { user { email } } }` also comes back with data, so both injection domains work.

Two findings worth keeping:

- **No binding was needed, unlike sentry and linear.** `sbx create` printed `Note: no binding authorizes buildkite — the credential was not injected`, and `~/.config/sbx/credentials.yaml` still lists only `linear` and `sentry` — yet injection demonstrably happened. The note is misleading for a `proxyManaged` kit credential; don't chase it. (There is no `.sbxenv.yaml` in the workspace, so no other binding source is in play.)
- **The proxy adds the header even when the client sends none.** A bare `curl https://api.buildkite.com/v2/user` from inside the sandbox returns **403** with genuine Buildkite response headers, where the same call from the host returns **401**. So the request was authenticated and only the `read_user` scope is missing from the token. Injection is therefore host-scoped, not CLI-scoped.

The supporting host-level checks, with `bk` run against an empty `HOME`/`XDG_CONFIG_HOME` to simulate the container:

- **`BUILDKITE_API_TOKEN` alone is enough.** With no config file and no keychain, `bk auth status` prints `Warning: using BUILDKITE_API_TOKEN environment variable for authentication` and then calls `GET https://api.buildkite.com/v2/access-token`. With no token at all it refuses up front: `Error: you are not authenticated. Run bk auth login to authenticate`.
- **No local token-format validation.** A junk token gets as far as a real 401 from the API, so the `proxy-managed` placeholder passes through to the proxy exactly like the sentry one.
- **`Bearer %s` is right for both hosts.** The CLI's own help documents `curl -H "Authorization: Bearer $(bk auth token)" https://api.buildkite.com/v2/user`.
- **Hosts are `api.buildkite.com` and `graphql.buildkite.com`** — the only two in the binary that `bk` calls (plus `github.com` for its `buildkite-agent` download helper, already open).
- **A stored token beats the env var, but can't exist in the container.** On the host, `BUILDKITE_API_TOKEN=fake bk auth status` still returned real data — the stored credential won. That's why there's no force-env flag: storing one needs a keychain (`OAuth login requires an available system keychain to persist your access token and refresh token`), so in the container the env var is the only source.
- **Org resolution.** In the `hub` checkout `bk` inferred `usabilityhub` with no config; in an empty non-git directory it warned `no organization set, only public pipelines will be visible`. Hence `BUILDKITE_ORGANIZATION_SLUG`.

## Notes and gotchas

- **`SENTRY_FORCE_ENV_TOKEN=1` is deliberate.** The sentry CLI's precedence is: forced env token → stored OAuth token → env token. Without the flag, a stray `sentry auth login` inside the sandbox would silently shadow the proxy credential.
- **`LINEAR_API_KEY` also dodges the keyring.** The linear CLI otherwise wants libsecret, which isn't there headlessly. The CLI prints `Warning: LINEAR_API_KEY environment variable is set` — harmless; the skill says to ignore it.
- **Linear's header format is `%s`, not `Bearer %s`.** Personal keys (`lin_api_*`) go in raw. An OAuth access token would need `Bearer %s`.
- **`linear.app` and `auth.linear.app` are deliberately blocked.** Only `api.linear.app` is open, so browser-opening commands won't work. The skill tells the agent to print the URL instead.
- **Use `--kit` at create time, not `sbx kit add`.** sbx has a known gap where `kit add` on a mixin skips the `agentContext` file (it gates on the artifact's own `aiFilename`, empty for mixins). The skills under `files/` are copied on both paths, so they survive either way — but the `agentContext` backstop only lands at create time.
- **`DENO_CERT` is load-bearing for the linear CLI.** sbx's egress proxy terminates TLS with its own CA and exports `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE`. The linear CLI is a compiled Deno binary and reads none of them, so it fails every request with `invalid peer certificate: UnknownIssuer` until `DENO_CERT` points at the bundle. The path assumes a Debian-family base image.
- **GitHub needs no kit credential, and must not have one.** sbx injects `GH_TOKEN` through a separate built-in GitHub-token mechanism — gh is authenticated with nothing declared in `credentials`. Declaring one anyway is a hard failure on four agents, because `credentials` merges as a union where duplicates error and `shell`, `copilot`, `docker-agent` and `opencode` each declare github themselves: `credential for service "github" defined in both "shell" and "toolkit"`. Verified both directions.
- **Never let a `.DS_Store` into `files/`.** sbx writes kit files through a shell command, so binary content kills container startup: `write file /home/agent/.DS_Store failed (exit 2): sh: 1: Syntax error: Unterminated quoted string`. `sbx kit validate` does **not** catch this — it passes, and then `create` fails with a 500. Any sync must strip `.DS_Store` and `._*`.
- **`BUILDKITE_ORGANIZATION_SLUG` is a convenience, not a requirement.** It only sets the default; `--pipeline usabilityhub/mobile-build` and the `{org}/{pipeline}/builds/{n}` form still override it per command. Drop it if you ever sandbox a repo in a different Buildkite org.
- **`bk` warns on every invocation.** `Warning: using BUILDKITE_API_TOKEN environment variable for authentication` is expected and harmless — same class as the linear CLI's env warning.
- **`buildkite.com` is deliberately blocked.** Only the two API hosts are open, so `bk` subcommands that open a browser won't work; the printed build URLs still do on the host.
- **Pinned versions.** The image build pins pi `0.82.1`, sentry `0.38.0`, linear `v2.3.0`, gh `v2.96.0` and bk `v3.44.1` in `docker/install-tools.sh`. Bump them there and rebuild/publish each agent image; nothing auto-updates.
- **`~/.claude` persistence.** Claude's base kit uses persistent named volumes. If a stale skills copy ever sticks around across recreates, that's why.

## Skills

`files/home/.claude/skills/` is a **straight mirror** of `~/.agents/skills/` — all nine host skills, copied verbatim. No sandbox-specific forks, no overrides.

That was a deliberate experiment and it passed. Earlier versions carried hand-written `sentry`, `linear` and `github` skills explaining the proxy auth model. They turned out to be unnecessary: both CLIs report themselves as authenticated inside the sandbox, so the host skills' existing auth branches behave correctly, and a cold agent completed real Linear and Sentry tasks with no extra guidance.

The payoff is that nothing can drift. An override would have frozen each skill at whatever was last hand-written and silently discarded upstream edits — which is exactly how the `linear` skill's `--assignee` / `--all-teams` guidance would have been lost.

To refresh after editing a host skill:

```sh
cd ~/projects/litterboxtoolkit/files/home/.claude/skills
rm -rf ./* && cp -RL ~/.agents/skills/* .
find . \( -name .DS_Store -o -name "._*" \) -delete
```

Existing sandboxes do not pick this up — remove and recreate.

There is intentionally no `agentContext` in `spec.yaml`, for the same reason: it would be one more hand-maintained description of behaviour, free to drift from what the kit actually does.
