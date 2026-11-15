{
  pkgs,
  lib,
  berkeleyMono,
  ...
}:
let
  # Berkeley Mono is licensed for one person and not redistributable, so the files live outside
  # this repo and come in through the `berkeleyMono` path input.
  berkeleyMonoPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "berkeley-mono";
    version = "2.004";
    src = berkeleyMono;

    dontConfigure = true;
    dontBuild = true;
    # home-manager's fontconfig reads $out/share/fonts.
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
  # Per-user: the license covers one person.
  home.packages = [ berkeleyMonoPkg ];
}
