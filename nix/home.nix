{ pkgs, ... }:
{
  home.username = "lyssna";
  home.homeDirectory = "/home/lyssna";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    # Hub's image supplies Linear, Pup, Buildkite, and Sentry. Keep only tools
    # that need the local Nix/Secret Service setup here.
    gh
    pi-coding-agent
    gnome-keyring
    dbus
    libsecret
  ];
}
