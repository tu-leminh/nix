# One-shot bootstrap of Argo CD + the argohome GitOps apps (replaces the
# ansible playbook). Idempotent: helm upgrade --install + kubectl apply, safe to
# re-run. If the SSH deploy key isn't in place yet it skips cleanly — copy the
# key, then: systemctl restart homelab-bootstrap.
{ pkgs, ... }:
let
  repoUrl = "git@github.com:tu-leminh/argohome.git";
  sshKey = "/home/mt/.ssh/id_ed25519";
  workDir = "/var/lib/homelab";
  repoDir = "${workDir}/argohome";
in
{
  systemd.services.homelab-bootstrap = {
    description = "Bootstrap Argo CD and the argohome GitOps apps";
    after = [ "k3s.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ kubectl kubernetes-helm git openssh ];
    environment = {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
      HOME = workDir;
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      GIT_SSH_COMMAND = "ssh -i ${sshKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      mkdir -p ${workDir}

      if [ ! -f ${sshKey} ]; then
        echo "Deploy key ${sshKey} missing; copy it in then: systemctl restart homelab-bootstrap" >&2
        exit 0
      fi

      until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 5; done

      # Install Argo CD only if it isn't already there. Once bootstrapped it
      # self-manages via the platform-bootstrap ApplicationSet and owns its own
      # ConfigMaps, so re-running `helm upgrade` loses a server-side-apply
      # ownership fight with argocd-controller and fails the whole unit — which
      # then stalls (~56s) and fails EVERY nixos-rebuild. Skipping when already
      # present keeps this genuinely idempotent/safe-to-re-run.
      #
      # The release is named core-argocd so this seed render is byte-identical
      # to Argo CD's self-managed render: the platform-bootstrap ApplicationSet
      # names this app {{path[1]}}-{{path.basename}} = core-argocd, and the
      # argo-cd chart derives resource names AND the app.kubernetes.io/instance
      # label from .Release.Name. Matching the name here means both renders
      # agree on names and on instance=core-argocd, so Argo CD adopts the seed
      # resources in place with no immutable-selector conflict (a prior
      # fullnameOverride hack fixed names but left the instance label split,
      # which made the redis NetworkPolicy drop the controller's traffic).
      #
      # No --wait: this unit is ordered Before=multi-user.target, so waiting for
      # Argo CD pods to be Ready would block the login prompt for minutes on
      # boot. helm applies all manifests (incl. CRDs) synchronously before
      # returning; pods come up asynchronously, which is what we want here.
      if ! kubectl -n core get deploy core-argocd-server >/dev/null 2>&1; then
        helm repo add --force-update argo https://argoproj.github.io/argo-helm
        helm repo update argo
        helm upgrade --install core-argocd argo/argo-cd \
          --namespace core --create-namespace \
          --set server.service.type=LoadBalancer \
          --set server.insecure=true
      fi

      # Argo CD repository credentials for the private repo (SSH deploy key).
      kubectl -n core create secret generic repo-argohome \
        --from-literal=type=git \
        --from-literal=url=${repoUrl} \
        --from-file=sshPrivateKey=${sshKey} \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl -n core label secret repo-argohome \
        argocd.argoproj.io/secret-type=repository --overwrite

      # Clone/refresh argohome and apply the App-of-Apps ApplicationSet.
      if [ -d ${repoDir}/.git ]; then
        git -C ${repoDir} pull --ff-only
      else
        git clone ${repoUrl} ${repoDir}
      fi
      kubectl apply -f ${repoDir}/bootstrap/applicationset.yaml
    '';
  };
}
