#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 --create <branch-name>
  $0 --connect <branch-name>
  $0 --continue <branch-name>
  $0 --recreate <branch-name>
  $0 --cleanup <branch-name>

--create creates a worktree at .claude/worktrees/<branch-name> and checks out
a new branch with that name. --connect opens a shell in an existing, running
worktree devcontainer. --continue reconnects to an existing worktree's
devcontainer, starting it when necessary. --recreate replaces the worktree's
primary devcontainer with the current local configuration while preserving its
Git worktree and Compose project volumes. --cleanup deletes that worktree's
containers and removes the local worktree without deleting either its local or
remote branch.
EOF
  exit 2
}

setup=false
connect_existing=false
continue_existing=false
recreate_existing=false
teardown=false
case "${1:-}" in
  --create)
    setup=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  --connect)
    connect_existing=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  --continue)
    continue_existing=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  --recreate)
    recreate_existing=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  --cleanup)
    teardown=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  *) usage ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
# This launcher is symlinked into Hub's ignored .devcontainer directory. Resolve
# the link so newly added local files are sourced from Litterbox even before a
# matching Hub-side symlink has been created.
local_devcontainer_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
local_config_files=(
  compose.local.yaml
  post-create.local.sh
  post-start.local.sh
)
local_config_fingerprint() {
  shasum -a 256 "${local_config_files[@]/#/$local_devcontainer_dir/}" \
    | shasum -a 256 \
    | awk '{ print $1 }'
}
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

if [[ "$connect_existing" == true ]]; then
  [[ -d "$worktree" ]] || {
    echo "Error: worktree does not exist: $worktree" >&2
    exit 1
  }

  network_devcontainer_config="$worktree/.devcontainer/network/devcontainer.json"
  [[ -f "$network_devcontainer_config" ]] || {
    echo "Error: network devcontainer configuration is missing from $worktree." >&2
    exit 1
  }

  devcontainer_args=(
    --workspace-folder "$worktree"
    --config "$network_devcontainer_config"
  )
  if ! devcontainer exec "${devcontainer_args[@]}" true; then
    echo "Error: devcontainer is not running for $branch. Start it with: $0 --continue $branch" >&2
    exit 1
  fi

  exec devcontainer exec "${devcontainer_args[@]}" \
    bash -lc 'cd /app && exec bash -l'
fi

prepare_host_credentials() {
  [[ -n "${SSH_AUTH_SOCK:-}" ]] || {
    echo "Error: SSH_AUTH_SOCK is not set." >&2
    echo "Start or select an SSH agent before creating or recreating a devcontainer." >&2
    return 1
  }

  [[ -S "$SSH_AUTH_SOCK" ]] || {
    echo "Error: SSH agent socket does not exist: $SSH_AUTH_SOCK" >&2
    return 1
  }

  command -v security >/dev/null || {
    echo "Error: macOS security CLI is not installed." >&2
    return 1
  }

  LINEAR_API_KEY="$(security find-generic-password \
    -a "$USER" \
    -s lyssna-linear-readonly \
    -w)" || {
    echo "Error: could not read LINEAR_API_KEY from the lyssna-linear-readonly Keychain item." >&2
    return 1
  }
  [[ -n "$LINEAR_API_KEY" ]] || {
    echo "Error: LINEAR_API_KEY from Keychain is empty." >&2
    return 1
  }
  export LINEAR_API_KEY

  GH_TOKEN="$(security find-generic-password \
    -a "$USER" \
    -s lyssna-github-cli \
    -w)" || {
    echo "Error: could not read GH_TOKEN from the lyssna-github-cli Keychain item." >&2
    return 1
  }
  [[ -n "$GH_TOKEN" ]] || {
    echo "Error: GH_TOKEN from Keychain is empty." >&2
    return 1
  }
  export GH_TOKEN

  # `bk auth login` uses a loopback OAuth callback inside the container, which a
  # host browser cannot reach. Use a dedicated read-only API token from the host
  # Keychain instead. Buildkite is optional, so do not prevent unrelated
  # devcontainer workflows when the token has not been configured yet.
  if BUILDKITE_API_TOKEN="$(security find-generic-password \
    -a "$USER" \
    -s lyssna-buildkite-readonly \
    -w 2>/dev/null)" && [[ -n "$BUILDKITE_API_TOKEN" ]]; then
    export BUILDKITE_API_TOKEN
  else
    unset BUILDKITE_API_TOKEN
    echo "Warning: Buildkite is unavailable. Add a read-only token to the lyssna-buildkite-readonly Keychain item." >&2
  fi

  for shared_volume in \
    lyssna-pnpm-store \
    lyssna-sentry
  do
    if ! docker volume inspect "$shared_volume" >/dev/null 2>&1; then
      echo "Creating shared volume: $shared_volume"
      docker volume create "$shared_volume" >/dev/null
    fi
  done
}

if [[ "$continue_existing" == true || "$recreate_existing" == true ]]; then
  [[ -d "$worktree" ]] || {
    echo "Error: worktree does not exist: $worktree" >&2
    exit 1
  }
elif [[ "$setup" == true ]]; then
  [[ ! -e "$worktree" ]] || {
    echo "Error: worktree already exists: $worktree" >&2
    echo "Reconnect with: $0 --continue $branch" >&2
    exit 1
  }

  mkdir -p "$(dirname "$worktree")"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Creating worktree from existing branch: $branch"
    git worktree add "$worktree" "$branch"
  else
    echo "Fetching origin/main..."
    git fetch origin main

    echo "Creating worktree on new branch: $branch"
    git worktree add -b "$branch" "$worktree" origin/main
  fi

  # Mobile config files are deliberately gitignored but required at runtime.
  # Seed every app's local config from the primary checkout into new worktrees.
  for source_config in "$repo_root"/mobile/apps/*/config.ts; do
    [[ -f "$source_config" ]] || continue

    relative_config_path="${source_config#"$repo_root"/}"
    target_config="$worktree/$relative_config_path"
    mkdir -p "$(dirname "$target_config")"
    cp "$source_config" "$target_config"
    echo "Copied mobile config: $relative_config_path"
  done

fi

# The repository's post-checkout hook may seed its own local overrides. Replace
# them with this launcher's paired setup so every worktree uses the same CLI
# installation and credential volumes.
for local_file in "${local_config_files[@]}"; do
  source_file="$local_devcontainer_dir/$local_file"
  target_file="$worktree/.devcontainer/$local_file"
  [[ -f "$source_file" ]] || {
    echo "Error: local devcontainer setup is missing $source_file" >&2
    exit 1
  }
  cp "$source_file" "$target_file"
 done
chmod +x \
  "$worktree/.devcontainer/post-create.local.sh" \
  "$worktree/.devcontainer/post-start.local.sh"

current_local_config_fingerprint="$(local_config_fingerprint)"
# Compose labels the container with this value. Pass it only to `devcontainer
# up`: the base host-side initializer rewrites .devcontainer/.env, so storing
# it there would be racy and would also expose launcher bookkeeping to Rails.
run_devcontainer_up() {
  prepare_host_credentials
  LOCAL_CONFIG_FINGERPRINT="$current_local_config_fingerprint" \
    devcontainer up "${devcontainer_args[@]}" "$@"
}

[[ -f "$worktree/.devcontainer/network/devcontainer.json" ]] || {
  echo "Error: network devcontainer configuration is missing from $worktree." >&2
  exit 1
}

network_devcontainer_config="$worktree/.devcontainer/network/devcontainer.json"
devcontainer_args=(
  --workspace-folder "$worktree"
  --config "$network_devcontainer_config"
)
local_config_label="lyssna.local_config_fingerprint"
# Identify the primary service by its Compose working directory instead of an
# inferred Dev Containers label, which is not present on Compose services.
existing_container="$(docker ps --all --quiet \
  --filter "label=com.docker.compose.project.working_dir=$worktree/.devcontainer" \
  --filter "label=com.docker.compose.service=rails-app" \
  | head -n 1)"

if [[ "$recreate_existing" == true ]]; then
  [[ -n "$existing_container" ]] || {
    echo "Error: devcontainer does not exist for $branch. Start it with: $0 --continue $branch" >&2
    exit 1
  }

  echo "Recreating devcontainer with current local configuration..."
  echo "Compose project volumes will be preserved. Container-local Pup credentials will be removed." >&2
  # Remove only the primary container. This avoids relying on Dev Containers'
  # inferred ID label, and leaves the Compose project's databases, caches, and
  # supporting services intact.
  docker rm --force "$existing_container" >/dev/null
  run_devcontainer_up
  existing_container="$(docker ps --all --quiet \
    --filter "label=com.docker.compose.project.working_dir=$worktree/.devcontainer" \
    --filter "label=com.docker.compose.service=rails-app" \
    | head -n 1)"
elif ! devcontainer exec "${devcontainer_args[@]}" true; then
  echo "Existing devcontainer is not running; starting it..."
  run_devcontainer_up
  existing_container="$(docker ps --all --quiet \
    --filter "label=com.docker.compose.project.working_dir=$worktree/.devcontainer" \
    --filter "label=com.docker.compose.service=rails-app" \
    | head -n 1)"
fi

# Existing containers predate fingerprint labels, and `--continue` deliberately
# keeps a healthy container running. In either case, make any configuration
# drift visible without silently applying it.
if [[ -n "$existing_container" ]]; then
  applied_local_config_fingerprint="$(docker inspect --format "{{ index .Config.Labels \"$local_config_label\" }}" "$existing_container")"
  if [[ "$applied_local_config_fingerprint" != "$current_local_config_fingerprint" ]]; then
    echo "Warning: local devcontainer configuration has changed since this container was created." >&2
    echo "This session uses the existing container configuration." >&2
    echo "Apply the current configuration with: $0 --recreate $branch" >&2
  fi
fi

echo "Configuring GitHub SSH host verification..."
# Pin GitHub's published Ed25519 host key rather than learning it with
# ssh-keyscan or StrictHostKeyChecking=accept-new. The latter would make a
# first-use connection vulnerable to a network-level man-in-the-middle attack.
devcontainer exec "${devcontainer_args[@]}" \
  bash -lc '
    set -euo pipefail
    ssh_dir="$HOME/.ssh"
    known_hosts="$ssh_dir/known_hosts"
    github_host_key="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

    install -d -m 700 "$ssh_dir"
    touch "$known_hosts"
    chmod 600 "$known_hosts"
    ssh-keygen -R github.com -f "$known_hosts" >/dev/null 2>&1 || true
    ssh-keygen -R "[github.com]:22" -f "$known_hosts" >/dev/null 2>&1 || true
    printf "%s\\n" "$github_host_key" >>"$known_hosts"
  '

echo "Verifying SSH agent forwarding..."
# `ssh-add -l` exits 1 when it can reach the agent but the agent has no
# identities. That must not prevent reconnecting to Pi: Pi can authenticate
# independently, and an identity can be added to the forwarded agent later.
devcontainer exec "${devcontainer_args[@]}" \
  bash -lc '
    ssh-add -l >/dev/null
    status=$?
    case "$status" in
      0) ;;
      1)
        echo "Warning: the forwarded SSH agent has no identities; Git-over-SSH will be unavailable until one is added." >&2
        ;;
      *) exit "$status" ;;
    esac
  '

echo "Pup is available with read-only OAuth when needed: pup auth login --read-only" >&2

echo "Devcontainer ready. Connecting..."
exec devcontainer exec "${devcontainer_args[@]}" \
  bash -lc 'cd /app && exec bash -l'
