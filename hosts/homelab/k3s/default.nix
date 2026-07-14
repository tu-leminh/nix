# Single-node k3s for the Argo CD home lab (~/argohome). Its own Traefik +
# MetalLB replace the bundled ones. Firewall is off, so no port rules.
{ config, pkgs, lib, ... }:
{
  imports = [ ./argocd.nix ];

  # Force Kubelet to create all new auto-generated hostPath directories as 777
  systemd.services.k3s.serviceConfig.UMask = lib.mkForce "0000";

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--write-kubeconfig-mode=0644"
      # overlayfs on bcachefs is unreliable for containerd's image layers;
      # native avoids overlayfs entirely (costs disk space/pull time instead).
      "--snapshotter=native"
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

  environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  environment.systemPackages = with pkgs; [ kubectl kubernetes-helm argocd k9s ];
}
