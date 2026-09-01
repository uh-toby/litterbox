#!/bin/bash
# Personal devcontainer customization

set -euo pipefail

# Linear and DataDog Pup are baked into the Hub devcontainer image. Their
# credentials remain configured by this trusted local overlay.

# Shared credential volumes are initially root-owned.
sudo mkdir -p "$HOME/.sentry"
sudo chown "$(id -u):$(id -g)" "$HOME/.sentry"

sudo mkdir -p "$HOME/.pi/agent"
sudo chown "$(id -u):$(id -g)" "$HOME/.pi/agent"
if [ ! -f "$HOME/.pi/agent/settings.json" ]; then
  cat > "$HOME/.pi/agent/settings.json" <<'EOF'
{
  "defaultProvider": "openrouter",
  "defaultModel": "openai/gpt-5.6-terra",
  "defaultThinkingLevel": "high"
}
EOF
fi

# Install Nix once into the persistent Linux store, then activate the
# Litterbox-pinned command-line tools in this container's Home Manager profile.
NIX_PROFILE="/nix/var/nix/profiles/devcontainer"
NIX_BIN="$NIX_PROFILE/bin/nix"
NIX_FLAKE="${LITTERBOX_NIX_FLAKE:?LITTERBOX_NIX_FLAKE must be set}"

sudo chown "$(id -u):$(id -g)" /nix
exec 9>/nix/.litterbox-nix.lock
flock 9

if [[ ! -x "$NIX_BIN" ]]; then
  echo "Installing Nix into persistent /nix volume..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install \
    | sh -s -- --no-daemon --yes --no-channel-add --no-modify-profile

  installed_nix="$(readlink -f "$HOME/.nix-profile/bin/nix")"
  mkdir -p "$(dirname "$NIX_PROFILE")"
  ln -sfn "${installed_nix%/bin/nix}" "$NIX_PROFILE"
fi

if ! "$NIX_BIN" store ping --store local >/dev/null 2>&1; then
  echo "Error: local Nix store is unavailable" >&2
  exit 1
fi

echo "Activating Home Manager configuration for lyssna..."
out="$("$NIX_BIN" build --no-link --print-out-paths "$NIX_FLAKE#homeConfigurations.lyssna.activationPackage")"
HOME_MANAGER_BACKUP_EXT=hm-bak "$out/activate"
