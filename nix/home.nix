{ pkgs, ... }:
{
  home.username = "lyssna";
  home.homeDirectory = "/home/lyssna";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    gh
    buildkite-cli
    sentry-cli
    pi-coding-agent
    gnome-keyring
    dbus
    libsecret

    # Nixpkgs names Sentry's executable `sentry-cli`; preserve the command name
    # used by the Sentry skill and the previous GitHub-release installation.
    (writeShellScriptBin "sentry" ''
      exec ${sentry-cli}/bin/sentry-cli "$@"
    '')
  ];
}
