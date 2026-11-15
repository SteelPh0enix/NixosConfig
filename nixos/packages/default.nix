{
  imports = [
    ./dev.nix
    ./media.nix
    ./system.nix
  ];

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
}
