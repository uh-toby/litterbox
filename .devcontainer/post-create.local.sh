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

# Install DataDog's Pup CLI from its latest GitHub release. Homebrew is not
# available in the devcontainer, and ~/.local/bin is already on PATH.
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

# Install Buildkite's CLI from its latest GitHub release. It reads the dedicated
# API token passed from the host Keychain; interactive OAuth cannot complete in
# this headless container because its loopback callback is container-local.
if [ -x "$HOME/.local/bin/bk-bin" ]; then
  mv -f "$HOME/.local/bin/bk-bin" "$HOME/.local/bin/bk"
fi
if ! command -v bk >/dev/null 2>&1; then
  case "$(uname -m)" in
    aarch64 | arm64) bk_arch="arm64" ;;
    x86_64) bk_arch="amd64" ;;
    *)
      echo "Error: unsupported architecture for Buildkite CLI: $(uname -m)" >&2
      exit 1
      ;;
  esac

  echo "Installing Buildkite CLI..."
  bk_tag="$(curl --proto '=https' --tlsv1.2 -LsS -o /dev/null -w '%{url_effective}' \
    https://github.com/buildkite/cli/releases/latest)"
  bk_tag="${bk_tag##*/}"
  bk_version="${bk_tag#v}"
  bk_archive="bk_${bk_version}_linux_${bk_arch}.tar.gz"
  bk_url="https://github.com/buildkite/cli/releases/download/${bk_tag}/${bk_archive}"
  bk_tmpdir="$(mktemp -d)"

  curl --proto '=https' --tlsv1.2 -LsSf "$bk_url" -o "$bk_tmpdir/$bk_archive"
  tar -xzf "$bk_tmpdir/$bk_archive" -C "$bk_tmpdir"
  install -m 755 "$(find "$bk_tmpdir" -type f -name bk -print -quit)" "$HOME/.local/bin/bk"
  rm -rf "$bk_tmpdir"
fi

# Install Sentry's CLI with its OAuth-capable `sentry auth` command. A separate
# scoped read-only token will be stored in its shared configuration volume.
if ! command -v sentry >/dev/null 2>&1; then
  case "$(uname -m)" in
    aarch64 | arm64) sentry_arch="arm64" ;;
    x86_64) sentry_arch="x64" ;;
    *)
      echo "Error: unsupported architecture for Sentry CLI: $(uname -m)" >&2
      exit 1
      ;;
  esac

  echo "Installing Sentry CLI..."
  sentry_tag="$(curl --proto '=https' --tlsv1.2 -LsS -o /dev/null -w '%{url_effective}' \
    https://github.com/getsentry/cli/releases/latest)"
  sentry_tag="${sentry_tag##*/}"
  sentry_url="https://github.com/getsentry/cli/releases/download/${sentry_tag}/sentry-linux-${sentry_arch}.gz"
  sentry_tmpfile="$(mktemp)"

  curl --proto '=https' --tlsv1.2 -LsSf "$sentry_url" | gzip -d >"$sentry_tmpfile"
  install -m 755 "$sentry_tmpfile" "$HOME/.local/bin/sentry"
  rm -f "$sentry_tmpfile"
fi

# Set up a headless system keyring (gnome-keyring's Secret Service over
# D-Bus) so OAuth-capable CLIs store credentials encrypted at rest. The local
# post-start hook starts and unlocks the one fixed session for this container.
if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
  echo "Installing gnome-keyring for system keyring support..."
  sudo apt-get update -qq
  sudo apt-get install --no-install-recommends -y gnome-keyring dbus-x11 libsecret-tools
fi

# Shared credential volumes are initially root-owned.
sudo mkdir -p "$HOME/.sentry"
sudo chown "$(id -u):$(id -g)" "$HOME/.sentry"

# Install Pi and persist its project-independent configuration and sessions in the
# worktree's named Docker volume (see compose.local.yaml).
if ! command -v pi >/dev/null 2>&1; then
  echo "Installing pi..."
  pnpm add --global @earendil-works/pi-coding-agent
fi

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
