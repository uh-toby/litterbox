#!/bin/sh
set -eu

# Keep these versions in sync with toolkit/README.md.
PI_VERSION=0.82.1
SENTRY_VERSION=0.38.0
LINEAR_VERSION=2.3.0
GH_VERSION=2.96.0
BK_VERSION=3.44.1

export DEBIAN_FRONTEND=noninteractive

npm install --global "@earendil-works/pi-coding-agent@${PI_VERSION}"

case "$(uname -m)" in
  aarch64|arm64) SENTRY_ARCH=arm64; LINEAR_ARCH=aarch64; GH_ARCH=arm64; BK_ARCH=arm64 ;;
  x86_64|amd64)  SENTRY_ARCH=x64; LINEAR_ARCH=x86_64; GH_ARCH=amd64; BK_ARCH=amd64 ;;
  *) echo "toolkit: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

curl -fsSL "https://github.com/getsentry/cli/releases/download/${SENTRY_VERSION}/sentry-linux-${SENTRY_ARCH}.gz" \
  | gzip -d > /usr/local/bin/sentry
chmod 0755 /usr/local/bin/sentry

# The Linear release is .tar.xz; slim base images may not include xz.
if ! command -v xz > /dev/null 2>&1; then
  apt-get update -qq > /dev/null
  apt-get install -y -qq --no-install-recommends xz-utils > /dev/null
  rm -rf /var/lib/apt/lists/*
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://github.com/schpet/linear-cli/releases/download/v${LINEAR_VERSION}/linear-${LINEAR_ARCH}-unknown-linux-gnu.tar.xz" \
  | tar -xJ -C "$tmp"
install -m 0755 "$(find "$tmp" -type f -name linear | head -n 1)" /usr/local/bin/linear
rm -rf "$tmp" && tmp=$(mktemp -d)

curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
  | tar -xz -C "$tmp"
install -m 0755 "$(find "$tmp" -type f -path '*/bin/gh' | head -n 1)" /usr/local/bin/gh
rm -rf "$tmp" && tmp=$(mktemp -d)

curl -fsSL "https://github.com/buildkite/cli/releases/download/v${BK_VERSION}/bk_${BK_VERSION}_linux_${BK_ARCH}.tar.gz" \
  | tar -xz -C "$tmp"
install -m 0755 "$(find "$tmp" -type f -name bk | head -n 1)" /usr/local/bin/bk
