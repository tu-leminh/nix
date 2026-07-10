# Accounts. Placeholder passwords — run `passwd` after first boot.
{ ... }:
{
  # Passwords are a single space — change with `passwd` after first boot.
  users.users.root.initialPassword = " ";

  users.users.mt = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = " ";
  };

  # ~/.ssh ready for you to drop in id_ed25519 (argohome deploy key) by hand.
  systemd.tmpfiles.rules = [ "d /home/mt/.ssh 0700 mt users -" ];
}
