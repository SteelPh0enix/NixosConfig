{
  inputs,
  settings,
  ...
}:
{
  # No blueman-applet: Noctalia talks to BlueZ directly (bluetooth widget, `bluetooth-*` IPC).
  services.gvfs.enable = true;

  services.openssh = {
    enable = true;
    ports = [ settings.sshPort ];
    openFirewall = true;
    settings = {
      X11Forwarding = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowUsers = [ settings.userName ];
      LogLevel = "VERBOSE";
    };
  };

  # Counterpart of the remote host's sshd AcceptEnv: without COLORTERM (WezTerm's truecolor hint)
  # TUIs over SSH fall back to the 256-colour palette. Kept system-wide, so ~/.ssh/config stays
  # hand-owned.
  programs.ssh.extraConfig = ''
    Host *
      SendEnv COLORTERM
  '';

  imports = [ inputs.ucodenix.nixosModules.default ];
  services.ucodenix = {
    enable = true;
    cpuModelId = "00A20F10";
  };

  services.flatpak.enable = true;
  services.fstrim.enable = true;
  services.irqbalance.enable = true;
  services.fwupd.enable = true;
}
