{
  systemd.timers."ci-runner-cache-prune" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
      Unit = "ci-runner-cache-prune.service";
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
