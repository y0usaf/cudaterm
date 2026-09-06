{ config, lib, ... }:
let cfg = config.user.ui.cudaterm;
in {
  options.user.ui.cudaterm = {
    enable = lib.mkEnableOption "CUDA terminal as the Finix desktop terminal";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Configured package providing cudaterm-finix";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = cfg.package != null; message = "cudaterm requires a configured package"; }
      { assertion = config.hardware.nvidia.enable; message = "cudaterm requires the NVIDIA driver"; }
    ];
    environment.systemPackages = lib.optional (cfg.package != null) cfg.package;
    user.defaults.terminal = lib.mkOverride 900 "cudaterm-finix";
    user.defaults.launcher = lib.mkDefault "cudaterm-finix --app-id=launcher -e ~/.config/scripts/tui-launcher.sh";
  };
}
