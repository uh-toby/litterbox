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

# Set up a headless system keyring (gnome-keyring's Secret Service over
# D-Bus) so CLIs like `linear auth login` can store credentials encrypted
# at rest instead of falling back to a plaintext credentials file.
#
# This container has no systemd/logind, so nothing normally starts a D-Bus
# session or the keyring daemon - keyring-init.sh (sourced from
# ~/.bashrc/~/.zshrc below) is that missing piece, started lazily on the
# first interactive shell of each container run.
if ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
  echo "Installing gnome-keyring for system keyring support..."
  sudo apt-get update -qq
  sudo apt-get install --no-install-recommends -y gnome-keyring dbus-x11 libsecret-tools
fi

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/keyring-init.sh" << 'KEYRING_INIT_EOF'
# Headless Secret Service (gnome-keyring) bootstrap, so CLIs like `linear`
# can store credentials in a real encrypted keyring instead of a plaintext
# config file. Must be *sourced*, not executed, so the exports/cd land in
# the calling shell. Safe to source repeatedly/from every shell: reuses a
# live session, only starts a new one if needed.
#
# This container has no systemd/logind, so nothing else creates
# XDG_RUNTIME_DIR or starts a D-Bus session or the keyring daemon - this
# script is that missing piece. Mirrored in
# .devcontainer/post-create.local.sh so a container rebuild reproduces it.

_keyring_dir="$HOME/.local/share/keyring-session"
_keyring_pass_file="$_keyring_dir/password"
_keyring_env_file="$_keyring_dir/env"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown "$(id -u):$(id -g)" "$XDG_RUNTIME_DIR"
    sudo chmod 700 "$XDG_RUNTIME_DIR"
fi

_keyring_alive() {
    [ -n "$DBUS_SESSION_BUS_ADDRESS" ] && dbus-send --session \
        --dest=org.freedesktop.DBus --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1
}

if [ -f "$_keyring_env_file" ]; then
    . "$_keyring_env_file"
fi

if ! _keyring_alive; then
    mkdir -p "$_keyring_dir"
    chmod 700 "$_keyring_dir"

    # Persistent (disk-encrypted) collection requires a real, non-empty
    # password - gnome-keyring silently refuses to create one from an empty
    # password. Generated once and kept file-permission-protected; nothing
    # ever prompts for it interactively.
    if [ ! -f "$_keyring_pass_file" ]; then
        (umask 177 && head -c32 /dev/urandom | base64 > "$_keyring_pass_file")
    fi

    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID

    eval "$(gnome-keyring-daemon --login --components=secrets,pkcs11,ssh < "$_keyring_pass_file")"
    export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK

    {
        echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'"
        echo "export DBUS_SESSION_BUS_PID='$DBUS_SESSION_BUS_PID'"
        echo "export GNOME_KEYRING_CONTROL='$GNOME_KEYRING_CONTROL'"
        echo "export SSH_AUTH_SOCK='$SSH_AUTH_SOCK'"
    } > "$_keyring_env_file"
    chmod 600 "$_keyring_env_file"
fi

unset -f _keyring_alive
unset _keyring_dir _keyring_pass_file _keyring_env_file
KEYRING_INIT_EOF

keyring_hook='if [ -f "$HOME/.local/bin/keyring-init.sh" ]; then . "$HOME/.local/bin/keyring-init.sh"; fi'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -q "keyring-init.sh" "$rc"; then
    printf '\n# Headless Secret Service for CLIs (e.g. `linear`) that store credentials\n# in a system keyring rather than a plaintext file. See\n# .devcontainer/post-create.local.sh for the one-time setup this relies on.\n%s\n' "$keyring_hook" >> "$rc"
  fi
done

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
