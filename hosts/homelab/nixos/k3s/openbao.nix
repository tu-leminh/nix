 Seed.*# Hands-free OpenBao bootstrap for argohome's apps/infra/openbao. A timer runs
 Seed.*# an idempotent oneshot that (1) generates the static-seal key once and
 Seed.*# publishes it as the Secret openbao-unseal-key, then (2) runs `bao operator
 Seed.*# init` once the pod reports a static seal. With a static seal the pod
 Seed.*# unseals itself on every restart, so no unseal step is ever manual.
 Seed.*#
 Seed.*# Key and init output (recovery keys + root token) live under tier1, so they
 Seed.*# survive a cluster rebuild with intact /data and ride along in the weekly
 Seed.*# Google Drive backup (../backup.nix) in plaintext - same trade-off as
 Seed.*# Vaultwarden's bootstrap credentials in argohome. Protect that account.
 Seed.*{ pkgs, ... }:
 Seed.*let
 Seed.*  dir = "/data/tier1/openbao/bootstrap";
 Seed.*in
 Seed.*{
 Seed.*  systemd.services.homelab-openbao-bootstrap = {
 Seed.*    description = "Seed OpenBao static-seal key and initialize it once";
 Seed.*    after = [ "k3s.service" "homelab-bootstrap.service" ];
 Seed.*    path = with pkgs; [ kubectl jq openssl coreutils ];
 Seed.*    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
 Seed.*    serviceConfig.Type = "oneshot";
 Seed.*    script = ''
 Seed.*      set -eu
 Seed.*      umask 077
 Seed.*
 Seed.*      # Argo CD (and so the infra namespace) may not exist yet; the timer retries.
 Seed.*      kubectl get ns infra >/dev/null 2>&1 || { echo "infra namespace not ready" >&2; exit 0; }
 Seed.*
 Seed.*      mkdir -p ${dir}
 Seed.*      [ -f ${dir}/unseal.key ] || openssl rand -out ${dir}/unseal.key 32
 Seed.*
 Seed.*      kubectl -n infra create secret generic openbao-unseal-key \
 Seed.*        --from-file=key=${dir}/unseal.key --dry-run=client -o yaml | kubectl apply -f -
 Seed.*
 Seed.*      phase=$(kubectl -n infra get pod infra-openbao-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)
 Seed.*      [ "$phase" = Running ] || { echo "infra-openbao-0 not running yet" >&2; exit 0; }
 Seed.*
 Seed.*      bao() { kubectl -n infra exec infra-openbao-0 -c openbao -- env BAO_ADDR=http://127.0.0.1:8200 bao "$@"; }
 Seed.*
 Seed.*      # `bao status` exits 2 while sealed/uninitialized, hence the || true.
 Seed.*      status=$(bao status -format=json 2>/dev/null || true)
 Seed.*      [ "$(echo "$status" | jq -r '.initialized')" = false ] || exit 0
 Seed.*
 Seed.*      # Never init under the default Shamir seal: it would emit unseal keys we
 Seed.*      # don't persist. Wait until argohome switches the pod to the static seal.
 Seed.*      [ "$(echo "$status" | jq -r '.type')" = static ] || { echo "seal is not static yet" >&2; exit 0; }
 Seed.*
 Seed.*      bao operator init -format=json > ${dir}/init.json.tmp
 Seed.*      mv ${dir}/init.json.tmp ${dir}/init.json
 Seed.*    '';
 Seed.*  };
 Seed.*
 Seed.*  systemd.timers.homelab-openbao-bootstrap = {
 Seed.*    wantedBy = [ "timers.target" ];
 Seed.*    timerConfig = {
 Seed.*      OnBootSec = "3min";
 Seed.*      OnUnitInactiveSec = "10min";
 Seed.*    };
 Seed.*  };
 Seed.*}
