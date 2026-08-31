#!/bin/bash
# Personal devcontainer customization

set -euo pipefail

# Install schpet/linear-cli so `linear` is available in the container shell.
# https://github.com/schpet/linear-cli
#
# LINEAR_INSTALL_DIR points the upstream installer at ~/.local (already on
# PATH via ~/.local/bin, same as mise) instead of its default ~/.cargo/bin.
if ! command -v linear >/dev/null 2>&1; then
  echo "Installing linear-cli..."
  curl --proto '=https' --tlsv1.2 -LsSf https://github.com/schpet/linear-cli/releases/latest/download/linear-installer.sh \
    | LINEAR_INSTALL_DIR="$HOME/.local" sh
fi

# Install DataDog's Pup CLI from its latest GitHub release. The Nix package
# named `pup` is an unrelated HTML parser, so it cannot replace this CLI.
# https://github.com/DataDog/pup
mkdir -p "$HOME/.local/bin"
# Earlier local setups wrapped Pup to lazily start Secret Service. A container
# recreation can retain the global pnpm volume, so restore the upstream binary
# before applying the fixed post-start session model.
if [ -x "$HOME/.local/bin/pup-bin" ]; then
  mv -f "$HOME/.local/bin/pup-bin" "$HOME/.local/bin/pup"
fi
if ! command -v pup >/dev/null 2>&1; then
  case "$(uname -m)" in
    aarch64 | arm64) pup_arch="arm64" ;;
    x86_64) pup_arch="x86_64" ;;
    *)
      echo "Error: unsupported architecture for Pup: $(uname -m)" >&2
      exit 1
      ;;
  esac

  echo "Installing DataDog Pup..."
  pup_tag="$(curl --proto '=https' --tlsv1.2 -LsS -o /dev/null -w '%{url_effective}' \
    https://github.com/DataDog/pup/releases/latest)"
  pup_tag="${pup_tag##*/}"
  pup_version="${pup_tag#v}"
  pup_archive="pup_${pup_version}_Linux_${pup_arch}.tar.gz"
  pup_url="https://github.com/DataDog/pup/releases/download/${pup_tag}/${pup_archive}"
  pup_tmpdir="$(mktemp -d)"

  curl --proto '=https' --tlsv1.2 -LsSf "$pup_url" -o "$pup_tmpdir/$pup_archive"
  tar -xzf "$pup_tmpdir/$pup_archive" -C "$pup_tmpdir" pup
  install -m 755 "$pup_tmpdir/pup" "$HOME/.local/bin/pup"
  rm -rf "$pup_tmpdir"
fi

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
