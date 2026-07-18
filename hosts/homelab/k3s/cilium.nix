# One-shot bootstrap of Cilium (CNI + kube-proxy replacement + Gateway API)
# plus the Gateway API CRDs it needs. Idempotent: kubectl apply + helm upgrade
# --install, safe to re-run. Must run before homelab-bootstrap (argocd.nix) -
# Cilium *is* the CNI, so no pod (including Argo CD's own) can schedule until
# it's up. LB-IPAM pool / L2Announcement / Gateway / HTTPRoutes are NOT
# scheduling prerequisites, so those stay GitOps-managed in argohome
# (apps/infra/cilium-lb, apps/infra/gateway) instead of living here.
{ pkgs, ... }:
let
  ciliumVersion = "1.19.6";
  gatewayApiVersion = "v1.6.1";
  # This node's own static LAN IP (network.nix) - Cilium's agents need this to
  # reach the apiserver directly since kube-proxy (and its Service routing)
  # is disabled.
  apiServerHost = "192.168.1.100";
  apiServerPort = "6443";
in
{
  systemd.services.homelab-cilium-bootstrap = {
    description = "Bootstrap Cilium (CNI, kube-proxy replacement, Gateway API)";
    after = [ "k3s.service" ];
    before = [ "homelab-bootstrap.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ kubectl kubernetes-helm ];
    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu

      until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 5; done

      # Gateway API CRDs - Cilium's Gateway controller needs these to exist
      # first; it doesn't bundle them itself. Must be the *experimental*
      # channel: Cilium 1.19's operator hard-fails at startup without the
      # TLSRoute CRD (gateway.networking.k8s.io/v1alpha2), which standard-
      # install.yaml doesn't include, even though we don't use TLSRoute.
      # --server-side is required too - Gateway API's CRDs are big enough
      # that client-side apply's last-applied-configuration annotation blows
      # past Kubernetes' annotation size limit.
      kubectl apply --server-side --force-conflicts -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${gatewayApiVersion}/experimental-install.yaml

      helm repo add --force-update cilium https://helm.cilium.io/
      helm repo update cilium
      helm upgrade --install cilium cilium/cilium \
        --version ${ciliumVersion} \
        --namespace kube-system \
        --set ipv4.enabled=true \
        --set ipv6.enabled=true \
        --set kubeProxyReplacement=true \
        --set k8sServiceHost=${apiServerHost} \
        --set k8sServicePort=${apiServerPort} \
        --set l2announcements.enabled=true \
        --set externalIPs.enabled=true \
        --set gatewayAPI.enabled=true \
        --set operator.replicas=1 \
        --set ipam.mode=kubernetes
    '';
  };
}
