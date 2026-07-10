# Static LAN on enp6s0 (no DHCP). WiFi/other links stay NetworkManager-managed.
# NOTE: 192.168.1.100 is the first IP of the argohome MetalLB pool
# (192.168.1.100-200). Move the node IP out of that range or start the pool at
# .101 to avoid MetalLB handing this address to a service.
{ ... }:
{
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = "enp6s0";
      autoconnect = true;
    };
    ipv4 = {
      method = "manual"; # no DHCP
      address1 = "192.168.1.100/24,192.168.1.1";
      dns = "192.168.1.1;";
    };
    ipv6.method = "auto";
  };
}
