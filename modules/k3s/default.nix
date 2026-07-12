# Single-node k3s for the Argo CD home lab (~/argohome). Its own Traefik +
# MetalLB replace the bundled ones. Firewall is off, so no port rules.
{ pkgs, ... }:
{
  imports = [ ./argocd.nix ./perm-fixer.nix ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--write-kubeconfig-mode=0644"
    ];
  };

  environment.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  environment.systemPackages = with pkgs; [ kubectl kubernetes-helm argocd k9s ];
}
