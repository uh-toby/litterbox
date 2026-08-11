#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 <branch-name>
  $0 --continue <branch-name>

Without --continue, creates a worktree at .claude/worktrees/<branch-name> and
checks out a new branch with that name. --continue reconnects to an existing
worktree's devcontainer, starting it when necessary.
EOF
  exit 2
}

continue_existing=false
case "${1:-}" in
  --continue)
    continue_existing=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  *)
    branch="${1:-}"
    [[ $# -eq 1 && -n "$branch" ]] || usage
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
worktree_slug="${branch//\//-}"
worktree="${repo_root}/.claude/worktrees/${worktree_slug}"
git check-ref-format --branch "$branch" >/dev/null

command -v devcontainer >/dev/null || {
  echo "Error: devcontainer CLI is not installed." >&2
  exit 1
}

[[ -n "${SSH_AUTH_SOCK:-}" ]] || {
  echo "Error: SSH_AUTH_SOCK is not set." >&2
  echo "Start or select an SSH agent before running this script." >&2
  exit 1
}

[[ -S "$SSH_AUTH_SOCK" ]] || {
  echo "Error: SSH agent socket does not exist: $SSH_AUTH_SOCK" >&2
  exit 1
}

command -v security >/dev/null || {
  echo "Error: macOS security CLI is not installed." >&2
  exit 1
}

LINEAR_API_KEY="$(security find-generic-password \
  -a "$USER" \
  -s lyssna-linear-readonly \
  -w)" || {
  echo "Error: could not read LINEAR_API_KEY from the lyssna-linear-readonly Keychain item." >&2
  exit 1
}
[[ -n "$LINEAR_API_KEY" ]] || {
  echo "Error: LINEAR_API_KEY from Keychain is empty." >&2
  exit 1
}
export LINEAR_API_KEY

if [[ "$continue_existing" == true ]]; then
  [[ -d "$worktree" ]] || {
    echo "Error: worktree does not exist: $worktree" >&2
    exit 1
  }
else
  [[ ! -e "$worktree" ]] || {
    echo "Error: worktree already exists: $worktree" >&2
    echo "Reconnect with: $0 --continue $branch" >&2
    exit 1
  }

  mkdir -p "$(dirname "$worktree")"
  echo "Fetching origin/main..."
  git fetch origin main

  echo "Creating worktree: $worktree"
  git worktree add -b "$branch" "$worktree" origin/main

  for file in \
    "$worktree/.devcontainer/post-create.local.sh" \
    "$worktree/.devcontainer/compose.local.yaml"
  do
    [[ -f "$file" ]] || {
      echo "Error: Husky did not seed $file" >&2
      exit 1
    }
  done
fi

[[ -f "$worktree/.devcontainer/network/devcontainer.json" ]] || {
  echo "Error: network devcontainer configuration is missing from $worktree." >&2
  exit 1
}

network_devcontainer_config="$worktree/.devcontainer/network/devcontainer.json"
devcontainer_args=(
  --workspace-folder "$worktree"
  --config "$network_devcontainer_config"
)

# `devcontainer exec` only succeeds when the existing container is running. Try
# it first so reconnecting does not recreate or restart a healthy container.
if ! devcontainer exec "${devcontainer_args[@]}" true; then
  echo "Existing devcontainer is not running; starting it..."
  devcontainer up "${devcontainer_args[@]}"
fi

echo "Verifying SSH agent forwarding..."
devcontainer exec "${devcontainer_args[@]}" \
  bash -lc 'ssh-add -l >/dev/null'

echo "Starting Pi..."
exec devcontainer exec \
  --workspace-folder "$worktree" \
  --config "$network_devcontainer_config" \
  bash -lc 'cd /app && exec pi'
