# llama.cpp router on the retained-PM4 ROCm/HIP build, served from the locally built image by
# the `llm` account's rootless Docker daemon. Container root maps to `llm`.
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
    # systemd reads the secret as root; the copy lands in StateDirectory, which rootlesskit does
    # not copy up.
    install -m 600 "$CREDENTIALS_DIRECTORY/api-key" "$STATE_DIRECTORY/api-key"
    export LLAMA_API_KEY_FILE="$STATE_DIRECTORY/api-key"
    # user@<uid> pulls the daemon in; wait for its socket.
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
    # Starts by hand; gufo is the boot engine. Conflicts= excludes the others; After= orders
    # their stop ahead of this start.
    wantedBy = [ ];
    after = [
      "llama-server-vulkan.service"
      "gufo.service"
      "gufo-auth.service"
      "network-online.target"
      "user@${uid}.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "user@${uid}.service" ];
    conflicts = [
      "llama-server-vulkan.service"
      "gufo.service"
      "gufo-auth.service"
    ];
    path = [ pkgs.coreutils ];

    environment = {
      DOCKER_HOST = "unix:///run/user/${uid}/docker.sock";
      XDG_RUNTIME_DIR = "/run/user/${uid}";
      HOME = llm.home;
      STRIX_PORT = toString settings.llmPort;
      STRIX_IMAGE = settings.llamaRocmImage;
      STRIX_MODELS_PATH = settings.llamaModelsPath;
      STRIX_INTERNAL_PORT = toString settings.llamaRocmContainerPort;
      STRIX_PRESET_PATH = settings.llamaRocmPresetsPath;
    };

    serviceConfig = {
      ExecStart = start;
      ExecStop = "${pkgs.docker}/bin/docker compose -p llama-server-rocm -f ${compose} down --remove-orphans --timeout 60";
      LoadCredential = "api-key:${settings.llmApiKeyFile}";
      # The key copy must outlive the credential dir, and /var is outside rootlesskit's copy-up
      # paths. Persisting it also keeps a manual `docker compose up` working.
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
