# Personal Hub devcontainer overlay

These files are symlinked into `~/projects/hub/.devcontainer/` and are copied into worktrees by `hub-workflow.local.sh`. They extend Hub's tracked devcontainer configuration with personal agent tooling and credentials.

## Trust model

All worktrees started with this overlay are trusted local development environments. They deliberately share credentials where that avoids repeated interactive authentication:

- GitHub CLI authentication is shared through Hub's `lyssna-gh` Docker volume. `GH_TOKEN` is also supplied from the macOS Keychain because tools and agent workflows may require it directly. It is a fine-grained, read-only token.
- The host SSH agent is forwarded. It currently contains only the GitHub SSH identity.
- Pi authentication, sessions, settings, and appended system prompt are shared from the host. `auth.json` and `APPEND_SYSTEM.md` are read-only; Pi writes session and settings metadata.
- Pup and Buildkite OAuth credentials, the Secret Service database, its password, and its D-Bus runtime state are per-container. Recreated containers need to authenticate again.
- Sentry's scoped credential volume is shared intentionally. Hub likewise shares GitHub CLI and AWS CLI state.
- The pnpm store is shared only as a package cache. Worktree `node_modules` remains isolated by Hub's base Compose configuration.

Do not use this overlay for untrusted repositories or code that should not be able to act as these shared identities.

## Host-mounted agent files

`~/Documents/agent-notes` is mounted read/write so agents in containers and on the host can share handovers and papercut records. `~/.agents` and the skills mounted at `~/.claude/skills` are mounted read-only because they are host-managed configuration.

## Local command-line tools

`post-create.local.sh` installs Linear CLI, Pup, Buildkite CLI, Sentry CLI, gnome-keyring, Secret Service tools, and Pi. These tools intentionally track their upstream latest releases in this personal overlay. A future Hub devcontainer-image improvement may install their executables and system dependencies during image build; personal configuration and authentication should remain in this overlay.

## Linear authentication

The `linear` CLI supports an API key supplied through `LINEAR_API_KEY`, or stores an API key in the system keyring after `linear auth login`. Its `auth login` command prompts for an API key; it has no OAuth or read-only authentication mode. The current Keychain-supplied API key is already read-only and remains the intended setup.
