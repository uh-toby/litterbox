#!/bin/bash
set -euo pipefail

# The Nix store is shared by trusted Hub worktrees. It must exist before
# Compose starts because compose.local.yaml declares it as an external volume.
docker volume inspect lyssna-nix >/dev/null 2>&1 ||
  docker volume create lyssna-nix >/dev/null
