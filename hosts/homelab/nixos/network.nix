# Static LAN on enp6s0 (no DHCP). WiFi/other links stay NetworkManager-managed.
# The node owns 10.0.0.100/16; argohome's Cilium LB-IPAM pool lives in a
# separate 10.0.1.0/24 range (10.0.1.2-255), so there is no overlap with the
# node address. The router forwards 80/443 directly to the Gateway's LB IP
# (10.0.1.2), which Cilium L2-announces, so no node-side DNAT is needed.
# (The former homelab-dnat double-NAT broke the reply path: the LB answers
# with src 10.0.1.2 while the router's NAT expected replies from 10.0.0.100.)
{ ... }:
{
  # Without this, NetworkManager races its own auto-created DHCP fallback
  # profile ("Wired connection 1") against the declarative "lan" profile at
  # boot and can win, leaving the node on a DHCP address instead of
  # 10.0.0.100 (breaking k3s's --node-ip and the Cilium LB pool).
  networking.networkmanager.settings.main.no-auto-default = "enp6s0";

  # AdGuard default server (blocks ads/trackers) via systemd-resolved + DoT.
  # The lan profile sets no DNS, so resolved's global servers apply; the
  # fallbacks are used only if every AdGuard server is unreachable.
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = [ "94.140.14.14" "94.140.15.15" "2a10:50c0::ad1:ff" "2a10:50c0::ad2:ff" ];
      FallbackDNS = [ "1.1.1.1" "8.8.8.8" ];
      DNSOverTLS = "yes";
    };
  };

  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = "enp6s0";
      autoconnect = true;
    };
    ipv4 = {
      method = "manual"; # no DHCP
      address1 = "10.0.0.100/16,10.0.0.1";
    };
    ipv6.method = "auto";
  };
}
