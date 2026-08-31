# Personal Hub devcontainer overlay

These files are symlinked into `~/projects/hub/.devcontainer/` and are copied into worktrees by `hub-workflow.local.sh`. They extend Hub's tracked devcontainer configuration with personal agent tooling and credentials.

## Trust model

All worktrees started with this overlay are trusted local development environments. They deliberately share credentials where that avoids repeated interactive authentication:

- GitHub CLI authentication is shared through Hub's `lyssna-gh` Docker volume. `GH_TOKEN` is also supplied from the macOS Keychain because tools and agent workflows may require it directly. It is a fine-grained, read-only token.
- The host SSH agent is forwarded. It currently contains only the GitHub SSH identity.
- Pi authentication, sessions, settings, and appended system prompt are shared from the host. `auth.json` and `APPEND_SYSTEM.md` are read-only; Pi writes session and settings metadata.
- Pup OAuth credentials, the Secret Service database, its password, and its D-Bus runtime state are per-container. Recreated containers need to authenticate Pup again.
- Buildkite uses a dedicated, read-only API token read from the host Keychain and passed as `BUILDKITE_API_TOKEN`. The CLI's interactive OAuth flow uses a loopback callback inside the container, so a host browser cannot complete it.
- Sentry's scoped credential volume is shared intentionally. Hub likewise shares GitHub CLI and AWS CLI state.
- The pnpm store is shared only as a package cache. Worktree `node_modules` remains isolated by Hub's base Compose configuration.
- Mise's versioned runtime installs and tool cache are shared. Mise reconciles the active Ruby, Node, and pnpm versions to each worktree's checked-out configuration, so version changes add new installs without overwriting an existing one.

Do not use this overlay for untrusted repositories or code that should not be able to act as these shared identities.

## Host-mounted agent files

`~/Documents/agent-notes` is mounted read/write so agents in containers and on the host can share handovers and papercut records. `~/.agents` and the skills mounted at `~/.claude/skills` are mounted read-only because they are host-managed configuration.

## Local command-line tools

Home Manager installs Buildkite CLI, Sentry CLI, Pi, gnome-keyring, D-Bus, and Secret Service tools from the Litterbox-pinned Nix flake. These immutable packages are shared through the Nix store while each container keeps its own Home Manager profile. `post-create.local.sh` still installs Linear CLI and DataDog Pup from their upstream latest releases: nixpkgs has no Linux Linear CLI package, and its unrelated `pup` package is an HTML parser. A future Hub devcontainer-image improvement may install their executables and system dependencies during image build; personal configuration and authentication should remain in this overlay.

## Nix

Nix manages tools in Hub devcontainers. It currently provides only a pinned, newer GitHub CLI from `../nix/flake.nix`.

## API-token authentication

Linear and Buildkite use dedicated, scope-limited API tokens supplied from the macOS Keychain by `hub-workflow.local.sh`. Buildkite's Keychain service is `lyssna-buildkite-readonly`; create or update it with:

```sh
security add-generic-password -U -a "$USER" -s lyssna-buildkite-readonly -w
```

Supply a Buildkite personal access token with only the read permissions required by the commands you run. The launcher leaves Buildkite unset, with a warning, until that Keychain item exists so it does not block unrelated worktrees.

The `linear` CLI supports an API key supplied through `LINEAR_API_KEY`, or stores an API key in the system keyring after `linear auth login`. Its `auth login` command prompts for an API key; it has no OAuth or read-only authentication mode. The current Keychain-supplied API key is already read-only and remains the intended setup.
