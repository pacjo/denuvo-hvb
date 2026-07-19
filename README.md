# Denuvo Hypervisor Bypass for NixOS

Hypervisor Bypass as a NixOS module based on DenuvOwO, LinUwUx and Pareidolia's work.


## Getting started

> [!IMPORTANT]
> Only flake based setups are supported. You're on your own if not using flakes.

1. Add to flake.nix:
  ```nix
  {
    inputs = {
      denuvo-hvb.url = "github:pacjo/denuvo-hvb";
    };
  }
  ```
2. Enable in configuration:
  ```nix
  services.denuvo-hvb = {
    enable = true;
    
    # everything auto-detected by default. Override as needed:
    # disableUmip = false;
    # cpuidFaultEmulation.enable = true;
    # cpuidFaultEmulation.autoLoad = true;
    # enableScripts = true;
  };
  ```

You'll need to add the input to modules. You can do this by adding `denuvo-hvb.nixosModules.default` to `modules` in `nixpkgs.lib.nixosSystem`.


## More sources/based on

- https://cs.rin.ru/forum/viewtopic.php?f=10&t=159989
- https://cs.rin.ru/forum/viewtopic.php?f=20&t=160056
- https://cs.rin.ru/forum/viewtopic.php?p=3550118#p3550118
