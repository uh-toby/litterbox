#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 --create <branch-name>
  $0 --connect <branch-name>
  $0 --continue <branch-name>
  $0 --cleanup <branch-name>

--create creates a worktree at .claude/worktrees/<branch-name> and checks out
a new branch with that name. --connect opens a shell in an existing, running
worktree devcontainer. --continue reconnects to an existing worktree's
devcontainer, starting it when necessary. --cleanup deletes that worktree's
containers and removes the local worktree without deleting either its local or
remote branch.
EOF
  exit 2
}

setup=false
connect_existing=false
continue_existing=false
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
  --cleanup)
    teardown=true
    branch="${2:-}"
    [[ $# -eq 2 && -n "$branch" ]] || usage
    ;;
  *) usage ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
local_devcontainer_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

GH_TOKEN="$(security find-generic-password \
  -a "$USER" \
  -s lyssna-github-cli \
  -w)" || {
  echo "Error: could not read GH_TOKEN from the lyssna-github-cli Keychain item." >&2
  exit 1
}
[[ -n "$GH_TOKEN" ]] || {
  echo "Error: GH_TOKEN from Keychain is empty." >&2
  exit 1
}
export GH_TOKEN

for datadog_credential in DD_API_KEY DD_APP_KEY; do
  case "$datadog_credential" in
    DD_API_KEY) keychain_service="lyssna-dd-api-key" ;;
    DD_APP_KEY) keychain_service="lyssna-dd-app-key" ;;
  esac
  credential_value="$(security find-generic-password \
    -a "$USER" \
    -s "$keychain_service" \
    -w)" || {
    echo "Error: could not read $datadog_credential from the $keychain_service Keychain item." >&2
    exit 1
  }
  [[ -n "$credential_value" ]] || {
    echo "Error: $datadog_credential from Keychain is empty." >&2
    exit 1
  }
  export "$datadog_credential=$credential_value"
done
unset credential_value keychain_service datadog_credential

for credential_volume in \
  lyssna-buildkite-keyrings \
  lyssna-buildkite-keyring-session \
  lyssna-sentry
 do
  if ! docker volume inspect "$credential_volume" >/dev/null 2>&1; then
    echo "Creating shared credentials volume: $credential_volume"
    docker volume create "$credential_volume" >/dev/null
  fi
 done

if [[ "$continue_existing" == true ]]; then
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
for local_file in \
  compose.local.yaml \
  post-create.local.sh
 do
  source_file="$local_devcontainer_dir/$local_file"
  target_file="$worktree/.devcontainer/$local_file"
  [[ -f "$source_file" ]] || {
    echo "Error: local devcontainer setup is missing $source_file" >&2
    exit 1
  }
  cp "$source_file" "$target_file"
 done
chmod +x "$worktree/.devcontainer/post-create.local.sh"

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

echo "Checking CLI authentication..."
devcontainer exec "${devcontainer_args[@]}" \
  bash -lc '
    set -euo pipefail
    if ! pup auth status >/dev/null; then
      echo "Pup is not authenticated. Run: pup auth login --read-only" >&2
    fi
    if ! bk auth status >/dev/null; then
      echo "Buildkite is not authenticated. Run: bk auth login --org usabilityhub --scopes read_only" >&2
    fi
    if ! sentry info --no-defaults >/dev/null; then
      echo "Sentry is not authenticated. Run: sentry login --global --auth-token <read-only-token>" >&2
    fi
  '

echo "Devcontainer ready. Connecting..."
exec devcontainer exec "${devcontainer_args[@]}" \
  bash -lc 'cd /app && exec bash -l'
