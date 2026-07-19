{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.denuvo-hvb;
  inherit (lib) mkOption mkEnableOption types mkIf;

  denuvo-hvb = pkgs.callPackage ../pkgs/denuvo-hvb {
    kernel = config.boot.kernelPackages.kernel;
  };

in
{
  options.services.denuvo-hvb = {
    enable = mkEnableOption "Denuvo hypervisor bypass for Linux gaming.";

    disableUmip = mkOption {
      type = types.bool;
      default = false;
      description = "Disables UMIP CPU feature.";
    };

    cpuidFaultEmulation = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Build and load the AMD CPUID fault emulation kernel module.";
      };

      autoLoad = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-load the module at boot via boot.kernelModules.";
      };
    };

    enableScripts = mkOption {
      type = types.bool;
      default = cfg.cpuidFaultEmulation.enable;
      description = "Install convenience scripts: denuvo-hvb-load, denuvo-hvb-unload, denuvo-hvb-status.";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelParams = mkIf cfg.disableUmip [ "clearcpuid=umip" ];

    boot.extraModulePackages = mkIf cfg.cpuidFaultEmulation.enable [ denuvo-hvb ];

    boot.kernelModules = mkIf
      (cfg.cpuidFaultEmulation.enable && cfg.cpuidFaultEmulation.autoLoad)
      [ "cpuid_fault_emulation" ];

    environment.systemPackages = mkIf cfg.enableScripts [
      (pkgs.writeShellScriptBin "denuvo-hvb-load" ''
        set -e
        if lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "cpuid_fault_emulation is already loaded" >&2
          exit 0
        fi
        echo "Loading cpuid_fault_emulation..."
        ${pkgs.kmod}/bin/modprobe cpuid_fault_emulation
        echo "Done."
      '')
      (pkgs.writeShellScriptBin "denuvo-hvb-unload" ''
        set -e
        if ! lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "cpuid_fault_emulation is not loaded" >&2
          exit 0
        fi
        echo "Unloading cpuid_fault_emulation..."
        ${pkgs.kmod}/bin/modprobe -r cpuid_fault_emulation
        echo "Done."
      '')
      (pkgs.writeShellScriptBin "denuvo-hvb-status" ''
        if lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "● cpuid_fault_emulation is LOADED"
        else
          echo "○ cpuid_fault_emulation is NOT loaded"
        fi
        echo "UMIP: $(grep -q 'clearcpuid=umip' /proc/cmdline && echo disabled || echo enabled)"
      '')
    ];
  };
}
