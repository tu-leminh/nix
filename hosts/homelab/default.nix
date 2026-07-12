# homelab — the installed machine: 5-disk bcachefs pool, GNOME + Sway,
# single-node K3s bootstrapping the argohome Argo CD stack.
{ ... }:
{
  imports = [
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/home.nix
    ../../modules/k3s
    ./disk.nix
    ./network.nix
  ];

  networking.hostName = "homelab";
  system.stateVersion = "26.11";
}
