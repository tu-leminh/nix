# Compressed RAM swap, preferred first (priority 100 > the 32G raw NVMe swap
# partition's priority 10 in ./storage.nix, which acts as overflow capacity for
# real sustained pressure rather than just absorbing spikes). No systemd-oomd:
# the two swap tiers are enough to keep the box from thrashing under GNOME +
# k3s + Argo CD memory pressure.
{ ... }:
{
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    priority = 100;
  };
}
