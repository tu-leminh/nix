# Single-node k3s for the Argo CD home lab (~/argohome). Cilium (installed by
# ./cilium.nix before Argo CD ever starts) replaces flannel as the CNI, plus
# kube-proxy and the bundled Traefik/servicelb - argohome's own
# apps/infra/cilium-lb + apps/infra/gateway replace MetalLB/Traefik on top of
# it. Firewall is off, so no port rules.
{ config, pkgs, lib, ... }:
{
  imports = [ ./argocd.nix ./cilium.nix ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--write-kubeconfig-mode=0644"
      "--snapshotter=stargz"
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      # Pod/service IPv6 are cluster-internal ULA ranges (RFC 4193) - separate
      # from the LAN's real /64, which is only used for LB-IPAM/Gateway
      # external addresses (see apps/infra/cilium-lb in argohome).
      "--cluster-cidr=10.42.0.0/16,fd42:42::/56"
      "--service-cidr=10.43.0.0/16,fd42:43::/112"
    ];
    # Let kubelet evict pods on reboot/shutdown instead of leaving containerd
    # sandboxes to be killed abruptly (which caused pods stuck
    # Unknown/SandboxChanged after reboot).
    gracefulNodeShutdown = {
      enable = true;
      shutdownGracePeriod = "90s";
      shutdownGracePeriodCriticalPods = "30s";
    };
  };

  # Tried zeroing UMask on this unit to make containerd's auto-created
  # hostPath bind-mount sources land 0777 instead of 0755 (default 0022).
  # Confirmed it does NOT work: even a freshly auto-created dir came back
  # root:root 0755 with Umask=0000 in effect, so containerd/kubelet must
  # reset its own umask internally before the mkdir. Don't retry this -
  # use the root initContainer chown pattern (see AGENTS.md) instead.

  environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  environment.systemPackages = with pkgs; [ kubectl kubernetes-helm argocd k9s ];
}
