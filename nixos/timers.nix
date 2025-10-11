{
  systemd.timers."refresh-dns" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
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

  systemd.timers."open-proton-ports" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnCalendar = "*-*-* *:*:00/30";
      AccuracySec="1s";
      Persistent = true;
      Unit = "open-proton-ports.service";
    };
  };

  systemd.services."open-proton-ports" = {
    script = "/root/open-wg-port.fish";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."rust-motd" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnCalendar = "*-*-* *:05:00";
      Persistent = true;
      Unit = "rust-motd.service";
    };
  };
}
