{ pkgs, ... }:
{
  home.username = "lyssna";
  home.homeDirectory = "/home/lyssna";
  home.stateVersion = "25.11";

  home.packages = [
    pkgs.gh
  ];
}
