# Hands-free OpenBao bootstrap for argohome's apps/infra/openbao. A timer runs
# an idempotent oneshot that (1) generates the static-seal key once and
# publishes it as the Secret openbao-unseal-key, then (2) runs `bao operator
# init` once the pod reports a static seal. With a static seal the pod
# unseals itself on every restart, so no unseal step is ever manual.
#
# Key and init output (recovery keys + root token) live under tier1, so they
# survive a cluster rebuild with intact /data and ride along in the weekly
# Google Drive backup (../backup.nix) in plaintext - same trade-off as
# Vaultwarden's bootstrap credentials in argohome. Protect that account.
{ pkgs, ... }:
let
  dir = "/data/tier1/openbao/bootstrap";
in
{
  systemd.services.homelab-openbao-bootstrap = {
    description = "Seed OpenBao static-seal key and initialize it once";
    after = [ "k3s.service" "homelab-bootstrap.service" ];
    path = with pkgs; [ kubectl jq openssl coreutils ];
    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077

      # Argo CD (and so the infra namespace) may not exist yet; the timer retries.
      kubectl get ns infra >/dev/null 2>&1 || { echo "infra namespace not ready" >&2; exit 0; }

      mkdir -p ${dir}
      # Raw 32 bytes. Replace a malformed key (an earlier version wrote hex)
      # only while OpenBao is uninitialized, i.e. nothing is encrypted with it.
      if [ ! -f ${dir}/unseal.key ] ||
         { [ ! -f ${dir}/init.json ] && [ "$(stat -c %s ${dir}/unseal.key)" != 32 ]; }; then
        openssl rand -out ${dir}/unseal.key 32
      fi

      kubectl -n infra create secret generic openbao-unseal-key \
        --from-file=key=${dir}/unseal.key --dry-run=client -o yaml | kubectl apply -f -

      phase=$(kubectl -n infra get pod infra-openbao-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)
      [ "$phase" = Running ] || { echo "infra-openbao-0 not running yet" >&2; exit 0; }

      bao() { kubectl -n infra exec infra-openbao-0 -c openbao -- env BAO_ADDR=http://127.0.0.1:8200 bao "$@"; }

      # `bao status` exits 2 while sealed/uninitialized, hence the || true.
      status=$(bao status -format=json 2>/dev/null || true)
      [ "$(echo "$status" | jq -r '.initialized')" = false ] || exit 0

      # Never init under the default Shamir seal: it would emit unseal keys we
      # don't persist. Wait until argohome switches the pod to the static seal.
      [ "$(echo "$status" | jq -r '.type')" = static ] || { echo "seal is not static yet" >&2; exit 0; }

      bao operator init -format=json > ${dir}/init.json.tmp
      mv ${dir}/init.json.tmp ${dir}/init.json
    '';
  };

  systemd.timers.homelab-openbao-bootstrap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitInactiveSec = "10min";
    };
  };
}
