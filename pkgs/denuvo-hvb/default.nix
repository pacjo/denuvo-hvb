{
  stdenv,
  lib,
  kernel,
  requireFile,
  rpmextract,
}:

stdenv.mkDerivation {
  pname = "denuvo-hvb";
  version = "0.1.0";

  src = requireFile {
    name = "cpuid-fault-emulation-dkms-0.1.0-1.fc44.noarch.rpm";
    sha256 = "nJArwJ+mi6YM5E7RNk87ETZf0hhZ/oQxgXsNA03e3uE=";
    url = "https://pixeldrain.com/l/TigZQb32#item=0";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ rpmextract ];

  hardeningDisable = [
    "pic"
    "format"
  ];

  unpackPhase = ''
    rpmextract $src
    cd usr/src/cpuid_fault_emulation-0.1.0
  '';

  # Patch the Makefile to use Nix store kernel paths instead of host paths
  postPatch = ''
    substituteInPlace Makefile \
      --replace '/lib/modules/$(KERNEL)/build' '${kernel.dev}/lib/modules/${kernel.modDirVersion}/build' \
      --replace '$(shell uname -r)' '${kernel.modDirVersion}'
  '';

  makeFlags = [ "KERNEL=${kernel.modDirVersion}" ];

  installPhase = ''
    install -Dm644 cpuid_fault_emulation.ko \
      "$out/lib/modules/${kernel.modDirVersion}/extra/cpuid_fault_emulation.ko"
  '';

  meta = {
    description = "AMD CPUID fault emulation kernel module for Denuvo bypass";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
  };
}
