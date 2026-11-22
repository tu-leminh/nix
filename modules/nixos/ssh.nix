{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # Keys only: the host is reachable over IPv6 from the internet. Both
      # must be off, or PAM keyboard-interactive still accepts passwords.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
