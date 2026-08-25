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

# Every invocation, including one executed directly by an agent rather than
# from a shell, must join the shared D-Bus/keyring session before Pup starts.
# Keep the upstream binary separate so this wrapper cannot recurse.
if [ -x "$HOME/.local/bin/pup" ] && [ ! -x "$HOME/.local/bin/pup-bin" ]; then
  mv "$HOME/.local/bin/pup" "$HOME/.local/bin/pup-bin"
fi
cat > "$HOME/.local/bin/pup" <<'PUP_WRAPPER_EOF'
#!/bin/sh
set -eu
# OAuth is the shared agent credential. Ignore legacy API-key variables from
# an already-running container until Compose can be recreated without them.
unset DD_API_KEY DD_APP_KEY
. "$HOME/.local/bin/keyring-init.sh"
exec "$HOME/.local/bin/pup-bin" "$@"
PUP_WRAPPER_EOF
chmod 755 "$HOME/.local/bin/pup"

# Install Buildkite's CLI from its latest GitHub release. It uses the system
# keyring for its refreshable OAuth credentials.
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
# Headless Secret Service (gnome-keyring) bootstrap. The first shell starts
# one D-Bus/keyring session for the container; later interactive and agent
# shells read the same connection details. This gives Pup's OAuth credentials
# the same authentication context in all processes.
#
# This container has no systemd/logind, so nothing else creates
# XDG_RUNTIME_DIR or starts a D-Bus session or the keyring daemon. Mirrored in
# .devcontainer/post-create.local.sh so a container rebuild reproduces it.

_keyring_dir="$HOME/.local/share/keyring-session"
_keyring_pass_file="$_keyring_dir/password"
_keyring_env_file="$_keyring_dir/environment"
_keyring_lock_file="$_keyring_dir/lock"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown "$(id -u):$(id -g)" "$XDG_RUNTIME_DIR"
    sudo chmod 700 "$XDG_RUNTIME_DIR"
fi

_keyring_alive() {
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && dbus-send --session \
        --dest=org.freedesktop.DBus --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1
}

_keyring_load_environment() {
    [ -r "$_keyring_env_file" ] || return 1
    # This file is written solely by this script with shell-quoted values.
    # shellcheck disable=SC1090
    . "$_keyring_env_file"
    _keyring_alive
}

mkdir -p "$_keyring_dir"
chmod 700 "$_keyring_dir"

# Always prefer the shared session over an inherited D-Bus address. A shell
# may have a live but private D-Bus session from before this setup; using it
# would make Pup prompt for a different, inaccessible keyring.
if ! _keyring_load_environment; then
    # Serialise setup so simultaneous agent subprocesses do not each create an
    # isolated session. Recheck after acquiring the lock.
    exec 9>"$_keyring_lock_file"
    flock 9
    if ! _keyring_load_environment; then
        # Persistent (disk-encrypted) collection requires a real, non-empty
        # password. Generated once and kept file-permission-protected; nothing
        # ever prompts for it interactively.
        if [ ! -f "$_keyring_pass_file" ]; then
            (umask 177 && head -c32 /dev/urandom | base64 > "$_keyring_pass_file")
        fi

        eval "$(dbus-launch --sh-syntax)"
        export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
        eval "$(gnome-keyring-daemon --login --components=secrets,pkcs11 < "$_keyring_pass_file")"
        export GNOME_KEYRING_CONTROL

        umask 177
        {
            printf 'export DBUS_SESSION_BUS_ADDRESS=%q\n' "$DBUS_SESSION_BUS_ADDRESS"
            printf 'export DBUS_SESSION_BUS_PID=%q\n' "$DBUS_SESSION_BUS_PID"
            printf 'export GNOME_KEYRING_CONTROL=%q\n' "$GNOME_KEYRING_CONTROL"
            printf 'export XDG_RUNTIME_DIR=%q\n' "$XDG_RUNTIME_DIR"
        } >"$_keyring_env_file"
    fi
    flock -u 9
    exec 9>&-
fi

unset -f _keyring_alive _keyring_load_environment
unset _keyring_dir _keyring_pass_file _keyring_env_file _keyring_lock_file
KEYRING_INIT_EOF

keyring_hook='if [ -f "$HOME/.local/bin/keyring-init.sh" ]; then . "$HOME/.local/bin/keyring-init.sh"; fi'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -q "keyring-init.sh" "$rc"; then
    printf '\n# Headless Secret Service for CLIs (e.g. `linear`) that store credentials\n# in a system keyring rather than a plaintext file. See\n# .devcontainer/post-create.local.sh for the one-time setup this relies on.\n%s\n' "$keyring_hook" >> "$rc"
  fi
done

# Shared credential volumes are initially root-owned.
sudo mkdir -p \
  "$HOME/.config/pup" \
  "$HOME/.local/share/keyrings" \
  "$HOME/.local/share/keyring-session" \
  "$HOME/.sentry"
sudo chown "$(id -u):$(id -g)" \
  "$HOME/.config/pup" \
  "$HOME/.local/share/keyrings" \
  "$HOME/.local/share/keyring-session" \
  "$HOME/.sentry"

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
