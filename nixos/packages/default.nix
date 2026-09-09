{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./dev.nix
    ./media.nix
    ./system.nix
  ];

  nixpkgs.overlays = [
    inputs.rust-overlay.overlays.default
    inputs.nix-cachyos-kernel.overlays.pinned
    inputs.llama-cpp.overlays.default
    (import ../overlays/llama-cpp.nix)
  ];

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.bat.enable = true;
  programs.cpu-energy-meter.enable = true;
  programs.dconf.enable = true;

  programs.direnv = {
    enable = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
  };

  programs.evince.enable = true;

  programs.fish.enable = true;

  programs.fzf.fuzzyCompletion = true;
  programs.fzf.keybindings = true;

  programs.gnupg.agent.enable = true;

  programs.java = {
    package = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
    enable = true;
    binfmt = true;
  };

  programs.less.enable = true;
  programs.nix-ld.enable = true;
  programs.npm.enable = true;
  programs.screen.enable = true;

  programs.tcpdump.enable = true;

  programs.wireshark = {
    enable = true;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    protontricks.enable = true;
    localNetworkGameTransfers.openFirewall = true;
    extest.enable = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
    extraPackages = with pkgs; [
      gamescope
      javaPackages.compiler.temurin-bin.jdk-25
    ];
  };

  qt.enable = true;
}
