# Host-agnostic NixOS base: bootloader, networking, users, SSH, packages.
# Per-host bits (hostname, stateVersion, disks) live under hosts/.
{ pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # bcachefs is pre-stable: the on-disk format tracks the kernel, and NixOS
  # asserts kernel >= 6.7 for it without auto-selecting one. Match the installer
  # (hosts/installer/default.nix), which formats the pool on linuxPackages_latest
  # — otherwise the installed system boots a different bcachefs version than the
  # one that created the pool and fails to mount /.
  boot.supportedFilesystems = [ "bcachefs" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Vendor firmware: amdgpu (GPU accel / Vulkan), Intel Bluetooth (ibt-*),
  # iwlwifi, and the r8169 NIC. Without it the GPU falls back to software
  # rendering (breaks GTK's Vulkan renderer) and Bluetooth/WiFi fail to init.
  hardware.enableRedistributableFirmware = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  nixpkgs.config.allowUnfree = true; # google-chrome, claude-code

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Asia/Ho_Chi_Minh";

  environment.systemPackages = with pkgs; [ bcachefs-tools keyutils git vim btop nushell ];

  # Users
  users.users.root.initialPassword = " ";
  users.users.mt = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = " ";
    shell = pkgs.nushell;
  };
  systemd.tmpfiles.rules = [ "d /home/mt/.ssh 0700 mt users -" ];

  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };
}
