{
  systemd.timers."refresh-dns" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnCalendar = "daily";
      Persistent = true;
      Unit = "refresh-dns.service";
    };
  };

  systemd.services."refresh-dns" = {
    script = "/root/update-dns.fish";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
