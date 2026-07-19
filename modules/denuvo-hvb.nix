{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.denuvo-hvb;
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  # Parse /proc/cpuinfo into a structured attrset.
  # Returns null if the file doesn't exist or can't be parsed.
  cpuInfo =
    if builtins.pathExists "/proc/cpuinfo" then
      let
        raw = builtins.readFile "/proc/cpuinfo";
        # Extract the first processor entry (all cores are typically identical)
        firstProc = lib.take 1 (lib.filter (l: l != "") (lib.splitString "\n\n" raw));
        procLines =
          if firstProc != [ ] then
            lib.filter (l: l != "" && lib.hasInfix ":" l) (lib.splitString "\n" (builtins.head firstProc))
          else
            [ ];
        # Parse "key : value" lines, stripping leading tabs
        parseLine =
          line:
          let
            parts = lib.splitString ":" line;
            key = lib.removePrefix "\t" (lib.trim (builtins.head parts));
            value = lib.removePrefix "\t" (lib.trim (lib.concatStringsSep ":" (builtins.tail parts)));
          in
          {
            name = key;
            value = {
              value = value;
            };
          };
        parsed = builtins.listToAttrs (map parseLine procLines);
      in
      if procLines != [ ] then parsed else null
    else
      null;

  # ─── CPU Identification ────────────────────────────────────

  cpuVendor =
    if cpuInfo != null then
      let
        raw = cpuInfo."vendor_id".value or "";
      in
      if lib.hasInfix "AMD" raw then
        "amd"
      else if lib.hasInfix "Intel" raw then
        "intel"
      else
        "unknown"
    else
      "unknown";

  cpuFamily = if cpuInfo != null then lib.toInt (cpuInfo."cpu family".value or "0") else 0;

  cpuModel = if cpuInfo != null then lib.toInt (cpuInfo."model".value or "0") else 0;

  modelName = if cpuInfo != null then cpuInfo."model name".value or "" else "";

  # AMD Zen generation detection
  #   Zen 1  (Ryzen 1000):   Family 23, Model 1, 17
  #   Zen+   (Ryzen 2000):   Family 23, Model 8
  #   Zen 2  (Ryzen 3000):   Family 23, Model 49, 96, 113
  #   Zen 3  (Ryzen 5000):   Family 25, Model 0–47, 80
  #   Zen 4  (Ryzen 7000):   Family 25, Model 97, 24, 17
  #   Zen 5  (Ryzen 9000):   Family 26
  amdZenGen =
    if cpuFamily == 23 then
      if cpuModel == 1 || cpuModel == 17 then
        1 # Zen 1
      else if cpuModel == 8 then
        1 # Zen+
      else if cpuModel == 49 || cpuModel == 96 || cpuModel == 113 then
        2 # Zen 2
      else
        2 # conservative for unknown family 23 models
    else if cpuFamily == 25 then
      if (cpuModel >= 0 && cpuModel <= 47) || cpuModel == 80 then
        3 # Zen 3
      else if cpuModel == 97 || cpuModel == 24 || cpuModel == 17 then
        4 # Zen 4
      else
        3 # conservative for unknown family 25 models
    else if cpuFamily == 26 then
      5 # Zen 5
    else
      0; # unknown

  # Intel generation detection via model name patterns.
  # Family/model mapping is complex for Intel, so we parse the marketing name.
  intelGen =
    let
      name = modelName;
    in
    if
      lib.hasInfix "i3-9" name
      || lib.hasInfix "i5-9" name
      || lib.hasInfix "i7-9" name
      || lib.hasInfix "i9-9" name
      || lib.hasInfix "N95" name
      || lib.hasInfix "N97" name
    then
      9
    else if
      lib.hasInfix "i3-10" name
      || lib.hasInfix "i5-10" name
      || lib.hasInfix "i7-10" name
      || lib.hasInfix "i9-10" name
    then
      10
    else if
      lib.hasInfix "i3-11" name
      || lib.hasInfix "i5-11" name
      || lib.hasInfix "i7-11" name
      || lib.hasInfix "i9-11" name
    then
      11
    else if
      lib.hasInfix "i3-12" name
      || lib.hasInfix "i5-12" name
      || lib.hasInfix "i7-12" name
      || lib.hasInfix "i9-12" name
      || lib.hasInfix "N100" name
      || lib.hasInfix "N200" name
      || lib.hasInfix "N300" name
    then
      12
    else if
      lib.hasInfix "i3-13" name
      || lib.hasInfix "i5-13" name
      || lib.hasInfix "i7-13" name
      || lib.hasInfix "i9-13" name
    then
      13
    else if
      lib.hasInfix "i3-14" name
      || lib.hasInfix "i5-14" name
      || lib.hasInfix "i7-14" name
      || lib.hasInfix "i9-14" name
    then
      14
    else if lib.hasInfix "Ultra" name then
      14 # Core Ultra / Meteor Lake+
    else if
      lib.hasInfix "i3-15" name
      || lib.hasInfix "i5-15" name
      || lib.hasInfix "i7-15" name
      || lib.hasInfix "i9-15" name
    then
      15
    else
      0; # unknown or too old

  # Steam Deck detection (Zen 2 custom APU: "AMD Custom APU 0405", etc.)
  isSteamDeck =
    (cpuVendor == "amd" && cpuFamily == 23 && cpuModel == 96)
    || lib.hasInfix "0405" modelName
    || lib.hasInfix "Aerith" modelName
    || lib.hasInfix "Sephiroth" modelName
    || lib.hasInfix "Galileo" modelName;

  # ─── Decision Logic ─────────────────────────────────────────

  # UMIP must be disabled for: Intel 9th gen+, AMD Zen 2+, Steam Deck
  shouldDisableUmip =
    (cpuVendor == "intel" && intelGen >= 9) || (cpuVendor == "amd" && amdZenGen >= 2) || isSteamDeck;

  # cpuid_fault_emulation kernel module needed for:
  #   AMD Zen 1–3 (AM4, pre-Zen 4), Steam Deck (Zen 2)
  # NOT needed for: Zen 4+ (hardware CPUID_FAULT), Intel (Broadwell+)
  shouldEnableCpuidFaultEmulation =
    (cpuVendor == "amd" && amdZenGen >= 1 && amdZenGen <= 3) || isSteamDeck;

  denuvo-hvb = pkgs.callPackage ../pkgs/denuvo-hvb {
    kernel = config.boot.kernelPackages.kernel;
  };

in
{
  options.services.denuvo-hvb = {
    enable = mkEnableOption ''
      Denuvo bypass support for Linux gaming.

      When enabled, this automatically:
      - Detects your CPU and applies appropriate configurations
      - Disables UMIP on supported CPUs (Intel 9th gen+, AMD Ryzen 3000+, Steam Deck)
      - Builds and installs the CPUID fault emulation kernel module
        for AMD CPUs without hardware support (AM4 < Ryzen 7000, Steam Deck)
    '';

    disableUmip = mkOption {
      type = types.bool;
      default = shouldDisableUmip;
      defaultText = "auto-detected from CPU";
      description = ''
        Disable UMIP (User Mode Instruction Prevention) via `clearcpuid=umip`
        kernel parameter.

        UMIP prevents userspace from executing SGDT, SIDT, SLDT, SMSW, and STR
        instructions. The Denuvo bypass needs SGDT to return a GDT limit of
        0x7F, which only works when UMIP is disabled.

        Auto-detected as enabled for: Intel 9th gen+, AMD Ryzen 3000+, Steam Deck.
      '';
    };

    cpuidFaultEmulation = {
      enable = mkOption {
        type = types.bool;
        default = shouldEnableCpuidFaultEmulation;
        defaultText = "auto-detected from CPU";
        description = ''
          Build and install the CPUID fault emulation kernel module.

          Required for CPUs without hardware CPUID_FAULT support:
          - AMD Ryzen AM4 (Zen 1, Zen+, Zen 2, Zen 3)
          - Steam Deck

          NOT needed for:
          - AMD Ryzen 7000+ (Zen 4+, has hardware CPUID_FAULT)
          - Intel CPUs (have hardware CPUID_FAULT since Broadwell, 5th gen)
        '';
      };

      autoLoad = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Auto-load the cpuid_fault_emulation module at boot.
          When disabled, manage the module manually with:
            denuvo-hvb-load / denuvo-hvb-unload
        '';
      };
    };

    enableScripts = mkOption {
      type = types.bool;
      default = cfg.cpuidFaultEmulation.enable;
      description = ''
        Install convenience scripts: denuvo-hvb-load, denuvo-hvb-unload,
        denuvo-hv-status.
      '';
    };
  };

  config = mkIf cfg.enable {
    # ── UMIP Disabling ────────────────────────────────────────
    boot.kernelParams = mkIf cfg.disableUmip [ "clearcpuid=umip" ];

    # ── CPUID Fault Emulation Kernel Module ───────────────────
    boot.extraModulePackages = mkIf cfg.cpuidFaultEmulation.enable [
      denuvo-hvb
    ];

    boot.kernelModules = mkIf (cfg.cpuidFaultEmulation.enable && cfg.cpuidFaultEmulation.autoLoad) [
      "cpuid_fault_emulation"
    ];

    # ── Convenience Scripts ──────────────────────────────────
    environment.systemPackages = mkIf cfg.enableScripts [
      (pkgs.writeShellScriptBin "denuvo-hvb-load" ''
        set -e
        if lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "cpuid_fault_emulation is already loaded" >&2
          exit 0
        fi
        echo "Loading cpuid_fault_emulation..."
        ${pkgs.kmod}/bin/modprobe cpuid_fault_emulation
        echo "Done. Module is now active."
      '')
      (pkgs.writeShellScriptBin "denuvo-hvb-unload" ''
        set -e
        if ! lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "cpuid_fault_emulation is not loaded" >&2
          exit 0
        fi
        echo "Unloading cpuid_fault_emulation..."
        ${pkgs.kmod}/bin/modprobe -r cpuid_fault_emulation
        echo "Done. Module has been removed."
      '')
      (pkgs.writeShellScriptBin "denuvo-hv-status" ''
        if lsmod | grep -q '^cpuid_fault_emulation\b'; then
          echo "● cpuid_fault_emulation is LOADED"
        else
          echo "○ cpuid_fault_emulation is NOT loaded"
        fi
        echo
        echo "CPU Vendor:  ${cpuVendor}"
        echo "Model:       ${modelName}"
        echo "UMIP:        $(grep -q 'clearcpuid=umip' /proc/cmdline && echo "disabled" || echo "enabled")"
      '')
    ];

    # ── Assertions ───────────────────────────────────────────
    assertions = [
      {
        assertion = cfg.cpuidFaultEmulation.enable -> cpuVendor == "amd";
        message = ''
          services.denuvo-hvb.cpuidFaultEmulation is enabled, but your CPU
          vendor is '${cpuVendor}'. The cpuid_fault_emulation kernel module
          only supports AMD CPUs with SVM extensions.
          Intel CPUs have hardware CPUID_FAULT and do not need this module.

          If you're sure you need this, set:
            services.denuvo-hvb.cpuidFaultEmulation.enable = true;
          explicitly to override.
        '';
      }
      {
        assertion = cfg.cpuidFaultEmulation.enable -> cpuVendor != "unknown";
        message = ''
          services.denuvo-hvb.cpuidFaultEmulation is enabled, but we could
          not detect your CPU (is /proc/cpuinfo available?). The module only
          supports AMD CPUs.

          If your CPU is AMD, set:
            services.denuvo-hvb.cpuidFaultEmulation.enable = true;
          explicitly to override.
        '';
      }
    ];

    # ── Warnings ─────────────────────────────────────────────
    warnings =
      lib.optional (cfg.disableUmip && !shouldDisableUmip) ''
        services.denuvo-hvb.disableUmip is enabled but your CPU
        (${modelName}) was not auto-detected as needing UMIP disabled.
        This may be intentional, or the auto-detection missed your CPU model.
      ''
      ++ lib.optional (cfg.cpuidFaultEmulation.enable && !shouldEnableCpuidFaultEmulation) ''
        services.denuvo-hvb.cpuidFaultEmulation is enabled but your CPU
        (${modelName}) was not auto-detected as needing the hypervisor module.
        Your CPU may already have hardware CPUID_FAULT support.
      ''
      ++ lib.optional (shouldEnableCpuidFaultEmulation && !cfg.cpuidFaultEmulation.enable) ''
        Your CPU (${modelName}) was detected as needing CPUID fault emulation,
        but cpuidFaultEmulation.enable is false. The Denuvo bypass may not work.
        Set services.denuvo-hvb.cpuidFaultEmulation.enable = true to enable.
      '';
  };
}
