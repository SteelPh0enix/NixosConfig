{
  pkgs,
  lib,
  berkeleyMono,
  ...
}:
let
  # Berkeley Mono is licensed for personal use by a single user and is not redistributable, so the
  # font files are kept outside this repo, in ~/nixos-nonfree/berkeley-mono (directory mode 700),
  # and pulled in through the `berkeleyMono` path input declared in flake.nix.
  #
  # Bootstrap on a fresh machine:
  #   1. put BerkeleyMono-{Regular,Bold,Oblique,Bold-Oblique}.ttf into ~/nixos-nonfree/berkeley-mono/
  #   2. nix flake update berkeleyMono                  # re-locks the content
  #   3. nixos-rebuild switch --flake .#steelph0enix-pc
  berkeleyMonoPkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "berkeley-mono";
    version = "2.004";
    src = berkeleyMono;

    dontConfigure = true;
    dontBuild = true;
    # $out/share/fonts is what home-manager's fonts.fontconfig.enable feeds to fc-cache.
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
  # Per-user on purpose: the license covers one person, so the font is not installed system-wide.
  # Icon/powerline glyphs come from nerd-fonts.symbols-only (OFL, declared in nixos/fonts.nix).
  home.packages = [ berkeleyMonoPkg ];
}
