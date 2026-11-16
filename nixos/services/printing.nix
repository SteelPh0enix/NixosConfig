{ pkgs, ... }:
{
  # mDNS for user-initiated printer discovery only: nothing inbound, nothing published, and
  # cups-browsed stays off (it queues from unauthenticated LAN traffic).
  services.avahi = {
    enable = true;
    openFirewall = false;
  };
  services.system-config-printer.enable = true;
  services.printing = {
    enable = true;
    startWhenNeeded = true;
    drivers = with pkgs; [
      gutenprint
      hplip
      splix
    ];
    browsed.enable = false; # would otherwise default to services.avahi.enable
    cups-pdf.enable = true;
  };
}
