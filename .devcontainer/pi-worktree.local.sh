#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 <branch-name>
  $0 --continue <branch-name>
  $0 --teardown <branch-name>

Without an option, creates a worktree at .claude/worktrees/<branch-name> and
checks out a new branch with that name. --continue reconnects to an existing
worktree's devcontainer, starting it when necessary. --teardown deletes that
worktree's containers and removes the local worktree without deleting either
its local or remote branch.
EOF
  exit 2
}

continue_existing=false
teardown=false
case "${1:-}" in
  --continue)
    continue_existing=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  --teardown)
    teardown=true
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

if [[ "$teardown" == true ]]; then
  [[ -d "$worktree" ]] || {
    echo "Error: worktree does not exist: $worktree" >&2
    exit 1
  }

  command -v docker >/dev/null || {
    echo "Error: Docker CLI is not installed." >&2
    exit 1
  }

  # Compose labels all services with its working directory and project name.
  # The devcontainer label is only on the primary service, so use it to find
  # every container and volume belonging to the worktree's Compose project.
  devcontainer_containers=()
  while IFS= read -r container; do
    [[ -n "$container" ]] && devcontainer_containers+=("$container")
  done < <(docker ps --all --quiet \
    --filter "label=devcontainer.local_folder=$worktree")

  compose_working_dirs=()
  compose_projects=()
  if [[ -n "${devcontainer_containers[*]:-}" ]]; then
    for container in "${devcontainer_containers[@]}"; do
      compose_working_dir="$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
        "$container")"
      compose_project="$(docker inspect \
        --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
        "$container")"

      if [[ -z "$compose_working_dir" || "$compose_working_dir" == "<no value>" ]]; then
        echo "Removing devcontainer: $container"
        docker rm --force "$container"
        continue
      fi

      if [[ -z "$compose_project" || "$compose_project" == "<no value>" ]]; then
        echo "Error: could not determine the Compose project for devcontainer: $container" >&2
        exit 1
      fi

      if [[ -n "${compose_working_dirs[*]:-}" ]]; then
        for known_working_dir in "${compose_working_dirs[@]}"; do
          [[ "$known_working_dir" == "$compose_working_dir" ]] && continue 2
        done
      fi
      compose_working_dirs+=("$compose_working_dir")
      compose_projects+=("$compose_project")
    done
  fi

  if [[ -n "${compose_working_dirs[*]:-}" ]]; then
    for compose_working_dir in "${compose_working_dirs[@]}"; do
      project_containers=()
      while IFS= read -r container; do
        [[ -n "$container" ]] && project_containers+=("$container")
      done < <(docker ps --all --quiet \
        --filter "label=com.docker.compose.project.working_dir=$compose_working_dir")

      if [[ -n "${project_containers[*]:-}" ]]; then
        echo "Removing devcontainer project in: $compose_working_dir"
        docker rm --force "${project_containers[@]}"
      fi
    done
  fi

  if [[ -n "${compose_projects[*]:-}" ]]; then
    for compose_project in "${compose_projects[@]}"; do
      project_volumes=()
      while IFS= read -r volume; do
        [[ -n "$volume" ]] && project_volumes+=("$volume")
      done < <(docker volume ls --quiet \
        --filter "label=com.docker.compose.project=$compose_project")

      if [[ -n "${project_volumes[*]:-}" ]]; then
        echo "Removing devcontainer volumes for project: $compose_project"
        docker volume rm "${project_volumes[@]}"
      fi
    done
  fi

  echo "Removing worktree: $worktree"
  git worktree remove "$worktree"
  exit 0
fi

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
