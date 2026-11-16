{
  pkgs,
  lib,
  berkeleyMono,
  ...
}:
let
  # Berkeley Mono is licensed to one person and is not redistributable, so the files live outside
  # this repo in ~/nixos-nonfree/berkeley-mono (mode 700), pulled in by the `berkeleyMono` path
  # input. On a fresh machine: put the four .ttf files there, `nix flake update berkeleyMono`,
  # rebuild.
  berkeleyMonoPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "berkeley-mono";
    version = "2.004";
    src = berkeleyMono;

    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -dm755 $out/share/fonts/truetype/berkeley-mono
      install -m644 *.ttf -t $out/share/fonts/truetype/berkeley-mono
      runHook postInstall
    '';

    meta = {
      description = "Berkeley Mono, installed from a local licensed copy";
      homepage = "https://usgraphics.com/products/berkeley-mono";
      license = lib.licenses.unfree;
      platforms = lib.platforms.all;
    };
  };
in
{
  # Per-user: the license covers one person. Icon glyphs come from nerd-fonts.symbols-only.
  home.packages = [ berkeleyMonoPkg ];
}
