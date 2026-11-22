# homelab — the installed machine: 6-disk bcachefs pool, GNOME + PaperWM,
# single-node K3s bootstrapping the argohome Argo CD stack.
{ pkgs, ... }:
{
  imports = [
    ../../../modules/nixos/base.nix
    ../../../modules/nixos/gnome.nix
    ../../../modules/nixos/home-manager.nix
    ../../../modules/nixos/ssh.nix
    ./gnome-policy.nix
    ./storage.nix
    ./storage-services.nix
    ./network.nix
    ./graphics.nix
    ./k3s
    ./vscode-tunnel.nix
    ./swap.nix
  ];

  networking.hostName = "homelab";
  system.stateVersion = "26.11";

  # bcachefs must use the same recent kernel as the installer that formats it.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "bcachefs" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.firewall.enable = false;

  environment.systemPackages = with pkgs; [ bcachefs-tools keyutils ];

  users.users.root.initialPassword = " ";
  users.users.mt = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = " ";
    # SSH is key-only (modules/nixos/ssh.nix), so the keys live here and
    # survive a reinstall; ~/.ssh/authorized_keys is still read as well.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFUEksvugWad68n76oOSw4DEezfUiRHgIPpjoD80Fqt tu-leminh@github"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkPAoAWcDe7JSl+UJPULdgAXMQw7wOnPsXcbatkn603"
    ];
  };
  systemd.tmpfiles.rules = [ "d /home/mt/.ssh 0700 mt users -" ];
  security.sudo.extraRules = [
    { users = [ "mt" ]; commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ]; }
  ];

  home-manager.users.mt.imports = [ ../home ];
}
