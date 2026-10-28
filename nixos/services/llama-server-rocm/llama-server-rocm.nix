# llama.cpp router on the retained-PM4 ROCm/HIP build (gfx1151), served from the locally built
# llama-rocm-10.1-strix-llama image by the `llm` account's own rootless Docker daemon. It is the
# third engine on settings.llmPort: it starts by hand and conflicts with both others, and container
# root maps to `llm` - not to the human account and not to root. The compose file comes from the
# store (the account cannot read the 0700 home); the preset comes from /home/LLMs.
{
  config,
  pkgs,
  settings,
  ...
}:
let
  llm = config.users.users.llm;
  uid = toString llm.uid;
  compose = "${./docker-compose.yml}";

  start = pkgs.writeShellScript "llama-server-rocm-up" ''
    set -euo pipefail
    # The secret stays 0600 on the human's account; systemd reads it as root and the copy lands in the
    # state directory, which rootlesskit does not copy up (unlike /run), so the daemon can bind it
    # into the container.
    install -m 600 "$CREDENTIALS_DIRECTORY/api-key" "$STATE_DIRECTORY/api-key"
    export LLAMA_API_KEY_FILE="$STATE_DIRECTORY/api-key"
    # user@<uid> pulls the daemon in; wait for its socket so a start right after boot is not a race.
    for _ in $(seq 1 60); do
      if [ -S "/run/user/${uid}/docker.sock" ]; then break; fi
      sleep 1
    done
    exec ${pkgs.docker}/bin/docker compose -p llama-server-rocm -f ${compose} up --remove-orphans
  '';
in
{
  systemd.services.llama-server-rocm = {
    description = "llama.cpp router server, ROCm container (${settings.llmHost}:${toString settings.llmPort})";
    documentation = [ "https://github.com/halo-box/strix-llama.cpp" ];
    # Starts by hand: gufo is the boot engine. A start still stops the other engines first —
    # Conflicts= is the exclusion; After= is what orders that stop ahead of this start
    # (Conflicts alone leaves the timing open, and every engine wants 51536 and the whole pool),
    # and ordering never starts the other units by itself.
    wantedBy = [ ];
    after = [
      "llama-server-vulkan.service"
      "gufo.service"
      "network-online.target"
      "user@${uid}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "user@${uid}.service" ];
    conflicts = [
      "llama-server-vulkan.service"
      "gufo.service"
    ];
    path = [ pkgs.coreutils ];

    environment = {
      # The image lives in this account's rootless daemon, not the system one.
      DOCKER_HOST = "unix:///run/user/${uid}/docker.sock";
      XDG_RUNTIME_DIR = "/run/user/${uid}";
      HOME = llm.home;
      STRIX_PORT = toString settings.llmPort;
      STRIX_PRESET_PATH = settings.llamaRocmPresetsPath;
    };

    serviceConfig = {
      ExecStart = start;
      ExecStop = "${pkgs.docker}/bin/docker compose -p llama-server-rocm -f ${compose} down --remove-orphans --timeout 60";
      LoadCredential = "api-key:${settings.llmApiKeyFile}";
      # The key copy has to outlive the credential directory, and /var is outside rootlesskit's
      # copy-up paths. Persisting it also keeps a manual `docker compose up` working.
      StateDirectory = "llama-server-rocm";
      StateDirectoryMode = "0700";
      User = llm.name;
      Group = "llm";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStopSec = 120;
    };
  };
}
