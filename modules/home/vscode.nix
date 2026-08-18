# VS Code Remote Tunnels are user-owned: the remote server, extensions, and
# GitHub credential all belong to the account that opens the workspace.
{ config, lib, ... }:
let
  cfg = config.services.vscode-tunnel;
in
{
  options.services.vscode-tunnel = {
    enable = lib.mkEnableOption "a persistent VS Code Remote Tunnel";

    executable = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path to the VS Code code CLI.";
    };

    tunnelName = lib.mkOption {
      type = lib.types.str;
      description = "Stable name shown by VS Code Remote Explorer.";
    };

    servicePath = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.package lib.types.str);
      default = [ ];
      description = "Packages and prefixes available to terminals opened through the tunnel.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.code-tunnel = {
      Unit = {
        Description = "VS Code Remote Tunnel (${cfg.tunnelName})";
        ConditionPathExists = "%h/.vscode/cli/token.json";
      };
      Service = {
        ExecStart = "${cfg.executable} tunnel --accept-server-license-terms --name ${cfg.tunnelName}";
        Restart = "always";
        RestartSec = 5;
        UMask = "0077";
        Environment = [
          "VSCODE_CLI_USE_FILE_KEYCHAIN=1"
          "PATH=${lib.makeBinPath cfg.servicePath}"
        ];
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
