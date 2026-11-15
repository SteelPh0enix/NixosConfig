# Crucible's release engine for gfx1151 and its Python front end. The runtime is gufo's ROCm 10.1
# package set, the one upstream checked the release engine on; taking the whole package from that
# one set keeps its glibc, libstdc++ and HIP runtime a single snapshot.
inputs: _final: prev:
let
  version = "0.37.0";
  rocm = import inputs.gufo.inputs.nixpkgs-rocm10.outPath {
    inherit (prev.stdenv.hostPlatform) system;
  };
  python = rocm.python3.withPackages (
    ps: with ps; [
      numpy
      jinja2
      tokenizers
      pillow
    ]
  );
in
{
  crucible = rocm.stdenv.mkDerivation {
    pname = "crucible";
    inherit version;

    src = rocm.fetchFromGitHub {
      owner = "jaedync";
      repo = "crucible-strix-halo";
      tag = "v${version}";
      hash = "sha256-Uv7/bM0zLc01hciLSdvY9fHJdpSYoOrgSK6WwyWHnWQ=";
    };

    engine = rocm.fetchurl {
      url = "https://github.com/jaedync/crucible-strix-halo/releases/download/v${version}/crucible-engine-v${version}-gfx1151-rocm7.2-linux-x86_64.gz";
      hash = "sha256-U6P7SRFB86QgXQljvBQwTm8dNFHV5OrPEb/JkxX6Uzo=";
    };

    nativeBuildInputs = [
      rocm.gzip
      rocm.makeWrapper
      rocm.autoPatchelfHook
    ];
    buildInputs = [
      rocm.rocmPackages_10.clr
      rocm.rocmPackages_10.rocm-comgr
      rocm.rocmPackages_10.rocm-runtime
      rocm.libdrm
      rocm.elfutils
      rocm.fmt
      rocm.glog
      rocm.numactl
      rocm.zstd
      rocm.zlib
      rocm.stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/crucible
      cp -r server VERSION $out/share/crucible/
      gzip -dc $engine > $out/share/crucible/engine
      chmod 755 $out/share/crucible/engine
      makeWrapper ${python}/bin/python3 $out/bin/crucible-server \
        --add-flags "-m server" \
        --prefix PYTHONPATH : "$out/share/crucible" \
        --set-default CRUCIBLE_NO_UPDATE_CHECK 1
      runHook postInstall
    '';

    meta = {
      description = "LLM inference engine for gfx1151";
      homepage = "https://github.com/jaedync/crucible-strix-halo";
      license = rocm.lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
    };
  };
}
