# Personal Hub devcontainer overlay

These files are symlinked into `~/projects/hub/.devcontainer/` and are copied into worktrees by `hub-workflow.local.sh`. They extend Hub's tracked devcontainer configuration with personal agent tooling and credentials.

## Trust model

All worktrees started with this overlay are trusted local development environments. They deliberately share credentials where that avoids repeated interactive authentication:

- Authorise `gh` once inside a trusted container with `gh auth login --with-token`. Git uses HTTPS and `gh` is its credential helper.
- Pi authentication, sessions, settings, and appended system prompt are shared from the host. `auth.json` and `APPEND_SYSTEM.md` are read-only; Pi writes session and settings metadata.
- Pup OAuth credentials, the Secret Service database, its password, and its D-Bus runtime state are per-container. Recreated containers need to authenticate Pup again.
- Buildkite uses a dedicated, read-only API token read from the host Keychain and passed as `BUILDKITE_API_TOKEN`. The CLI's interactive OAuth flow uses a loopback callback inside the container, so a host browser cannot complete it.
- Sentry's scoped credential volume is shared intentionally. Hub likewise shares GitHub CLI and AWS CLI state.
- The pnpm store is shared only as a package cache. Worktree `node_modules` remains isolated by Hub's base Compose configuration.
- Playwright's browser cache is shared. Playwright stores browser revisions separately and `pnpm exec playwright install chromium` installs the revision required by the worktree, so compatible downloads are reused without forcing a browser version across worktrees.
- Mise's versioned runtime installs and tool cache are shared. Mise reconciles the active Ruby, Node, and pnpm versions to each worktree's checked-out configuration, so version changes add new installs without overwriting an existing one.

Do not use this overlay for untrusted repositories or code that should not be able to act as these shared identities.

## Host-mounted agent files

`~/Documents/agent-notes` is mounted read/write so agents in containers and on the host can share handovers and papercut records. `~/.agents` and the skills mounted at `~/.claude/skills` are mounted read-only because they are host-managed configuration.

## Local command-line tools

The Hub image installs Linear, DataDog Pup, Buildkite CLI, and Sentry CLI during its build, verifying downloaded release artefacts against upstream checksum metadata. The Litterbox-pinned Nix flake supplies Pi, gnome-keyring, D-Bus, Secret Service tools, and a newer GitHub CLI. Its immutable packages are shared through the Nix store while each container keeps its own Home Manager profile. Personal configuration and authentication remain in this overlay.

## Nix

Nix manages the local-only tools in Hub devcontainers: Pi and the Secret Service dependencies, plus a pinned newer GitHub CLI from `../nix/flake.nix`.

## GitHub CLI authentication

Hub's `origin` must use HTTPS. On the host, set it once with:

```sh
git -C ~/projects/hub remote set-url origin https://github.com/wearelyssna/hub.git
```

In one trusted Hub devcontainer, authenticate the shared `lyssna-gh` volume:

```sh
gh auth login --hostname github.com --with-token
```

Use a fine-grained personal access token owned by `wearelyssna`, restricted to the Hub repositories agents need. Grant `Contents` read/write, `Pull requests` read/write, `Issues` read/write, `Actions` read-only, and `Commit statuses` read-only. Grant `Discussions` only when agents need GitHub Discussions. Do not grant administration, secrets, variables, webhooks, environments, deployments, or workflow permissions.

`post-create.local.sh` configures `gh` as Git's HTTPS credential helper in every container. The login is required only once: later containers use the shared authenticated volume.

## API-token authentication

Linear and Buildkite use dedicated, scope-limited API tokens supplied from the macOS Keychain by `hub-workflow.local.sh`. Buildkite's Keychain service is `lyssna-buildkite-readonly`; create or update it with:

```sh
security add-generic-password -U -a "$USER" -s lyssna-buildkite-readonly -w
```

Supply a Buildkite personal access token with only the read permissions required by the commands you run. The launcher leaves Buildkite unset, with a warning, until that Keychain item exists so it does not block unrelated worktrees.

The `linear` CLI supports an API key supplied through `LINEAR_API_KEY`, or stores an API key in the system keyring after `linear auth login`. Its `auth login` command prompts for an API key; it has no OAuth or read-only authentication mode. The current Keychain-supplied API key is already read-only and remains the intended setup.
