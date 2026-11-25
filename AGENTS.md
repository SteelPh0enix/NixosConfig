# Working in this repo

Rules and traps for changing `~/nixos-config`. `README.md` says what the machine is and runs; read it
first if that is not obvious yet.

## One repo, two machines

This flake builds `RX-78-FPC` (`steelph0enix.framework`) and nothing else. `steelph0enix.pc` is a
separate box with its own checkout, its own presets and its own `--parallel`: nothing here changes it,
and what its servers answer is not evidence about the ones on this machine.

## Checking a change

```bash
# one option, cheap
nix eval --raw .#nixosConfigurations.RX-78-FPC.config.networking.hostName
nix eval .#nixosConfigurations.RX-78-FPC.config.systemd.services.llama-server-vulkan.serviceConfig.Restart

nh os switch        # build the system and activate it now, home-manager files included
nh os boot          # build it and make it the default boot entry; apply on reboot

# the real check for a system change, and a heavy build
nix build .#nixosConfigurations.RX-78-FPC.config.system.build.toplevel --no-link
```

`nix flake check` evaluates every output, so it drags the whole system config along and stops on any
`path:` input that no longer evaluates.

Format `.nix` with `nixfmt`, lint with `statix` and `deadnix`, and `shellcheck` the scripts defined in
`home-manager/shell.nix` — all of them are in `nix develop`. `nixfmt` reports one difference in
`home-manager/pi/default.nix` that predates this style of writing (a long `entryAfter` line); leave it
rather than reflow a file you barely touched. Keep the surrounding style: options in alphabetical-ish
groups, and the file's own comment style, which explains *why* rather than *what*.

## Do not

- **Read, print or copy anything in `secrets/`,** and never inline a secret value in a `.nix`. The
  shape is always: a path in the config, the value in `secrets/` (or pi's `apiKey: "!command"`). A new
  secret is created by hand at mode 0600, and the commit records the path, never the value.
- Run `nix flake update` casually. `pi` has no binary cache, so it costs minutes of local building;
  `llama-cpp` and `berkeleyMono` are `path:` inputs pinned by narHash in `flake.lock`, so
  `nix flake update <input>` re-pins the current directory - `llama-cpp-update` does that for llama.cpp
  (see the README). The kernel is `linuxPackages_xanmod_latest` from cache.nixos.org, so a `nixpkgs`
  bump normally just substitutes it; the `nix-cachyos-kernel` flake is gone because its author's
  cache and Hydra were compromised. If a kernel must be frozen, the pin goes in `flake.nix` with the
  reasoning, not quietly in `flake.lock`. `gufo` has no cache either, so it is the expensive input.
- Hand-edit `~/.pi/agent/settings.json` to change a managed setting. Edit `home-manager/pi/default.nix`
  and re-activate; a hand-edit in the live file only gets shadowed by the managed key again.

## The llama.cpp servers

The Vulkan engine is a NixOS unit (`llama-server-vulkan`), built from the `llama-cpp` flake input
by `nix/overlays/llama-cpp.nix` — Vulkan only, `-march=znver5` (x86-64-v4 is not enough for the
AVX512 extensions here), LTO — running as the `llm` user with
`--slots --props --metrics --models-max 1 --webui`. It starts by hand like the other three engines;
`settings.defaultLlmEngine` (`nix/settings/llm.nix`) names the one that boots with the system. Keep
autoload on: with it off the server answers
`400 "model is not loaded"` instead of loading a named preset. Its process is sandboxed
(`ProtectSystem=strict`, `ProtectHome=read-only`, `LimitMEMLOCK=infinity`, `MemoryDenyWriteExecute`
off for the Vulkan JIT, `GGML_VK_VISIBLE_DEVICES=0` because llvmpipe shows up as a second device).
A start stops the other three engines first (`Conflicts=`/`After=`) so a model loaded here does not
land on top of theirs. It authenticates with `secrets/llama-strix-api-key` via `--api-key-file`,
fed by a systemd credential.

Weights and the presets live in `/home/LLMs` for that reason: the unit runs as `llm` and cannot
traverse a 0700 home. The checkout keeps a **symlink** to each preset, so editing presets is an
edit plus a restart of the unit, and no rebuild.

Crucible (`nixos/services/crucible.nix`) is the boot engine and holds the GPU from boot: the release
binary from jaedync/crucible-strix-halo, packaged by `nix/overlays/crucible.nix` over gufo's own ROCm
10.1 set (`inputs.gufo.inputs.nixpkgs-rocm10`) rather than nixpkgs' 7.2.4, because that is the runtime
upstream checked the release engine on; the Python front end comes from that same set, so its glibc and
libstdc++ are one snapshot with the HIP runtime. It is not built from source: upstream only qualifies
a source build with the 7.2.4 compiler. It serves Qwen3.8-Flash-Next from the EXL3 4.05 bpw pack
(`4.05bpw_h6_ng6` under `/home/crucible/models/qwen/3.8-Flash-Next/`) in **two** 262144-token sessions
(`--streams ${settings.crucibleStreams}`) - measured 2026-11-25 with both slots filled to ~250k:
GTT peaked at 94.7 of 124 GiB and nothing OOMed (cgroup `oom_kill 0`, kernel OOM 0, MemAvailable
floor 18 GiB), so 2 fits; the 2026-11-15 OOM at 92.5 GiB was a second slot on top of GTT a
SIGKILLed predecessor still held. It binds `llmPort` itself and checks the Bearer key with
`--api-key-file`, so unlike gufo there is
no caddy front door: the unit copies `secrets/llama-strix-api-key` into `/var/lib/crucible/api-key`,
and rotating it means restarting `crucible`. Everything of the engine sits in its own home
`/home/crucible` (`llm`-owned, 0700): the pack under `models/qwen/3.8-Flash-Next/`, and the
conversation cache at `/home/crucible/crucible-states` (`--state-dir`, 200 GiB), writable through
`ProtectHome=read-only` by being named in `ReadWritePaths`. Crucible 0.38 accepts a `--state-dir`
outside `$HOME` but refuses one whose parent chain anyone but its user or root can change, which
rules out the human-owned `/home/LLMs`, so the unit sets `HOME=/home/crucible` - move that variable
with the directory, not just the flag. Version and both hashes sit in the overlay, not in a flake input, so
`nh os switch` needs no network; `crucible-update` resolves the newest release, rewrites those three
values and leaves the file alone when it is already current.

Gufo (`nixos/services/gufo.nix`) is the second engine on the same **51536**: built from the `gufo`
flake input, serving Qwen3.8-Flash-Next with its shared MTP sidecar. It starts by hand, taking its
262144-token session with it. The
rootless-Docker llama.cpp router it replaced now lives in the repo as
`nixos/services/llama-server-rocm/` (below); `~/LLMs/llm-router-docker-compose.yml` is kept only as
the manual rollback copy, on the human account and port 44444. Gufo has no binary cache, so a `gufo`
bump is a long local build. The API key is `secrets/llama-strix-api-key`, the same one llama.cpp
serves with (the retired `.env` kept it as `STRIX_API_KEY`); gufo 0.31 dropped `--api-key`
entirely (gufo-org/gufo#957), so gufo binds loopback-only behind gufo-auth, a caddy unit that
owns llmPort and checks the Bearer key — the key is no longer visible in any process command
line, and rotating it is a `systemctl restart gufo-auth` that leaves the weights loaded. Its
continuation cache is capped with `--cache-ram-bytes`
(the automatic budget is half of `MemAvailable` and throws the host into swap, gufo-org/gufo#387),
and `--stall-timeout-ms` exits a generation that stops progressing as `device_lost` so systemd
restarts the engine. It runs as `llm`, the same account as the Vulkan server (`nixos/users.nix`),
and on the same `llmPort` (51536); the units conflict, so only one engine is up at a time.

The third llama.cpp engine is the ROCm container (`nixos/services/llama-server-rocm/`), the retained-PM4
HALO build from halo-box/strix-llama.cpp and the fastest of them on this APU. Its image
`llama-rocm-10.1-strix-llama` has no registry: `llama-rocm-image-update` clones or pulls
`/home/LLMs/amd-strix-halo-toolboxes`, runs the toolboxes `docker build --no-cache`, and loads the
result into `llm`'s own rootless Docker daemon (`linger` plus the subuid range in
`nixos/users.nix`). The unit reads its compose from the store (that account cannot read the 0700
home), publishes `llmPort` and mounts `/home/LLMs` read-only; its preset is
`llama-server-rocm.ini`. It conflicts with the other three engines; the
same key reaches it, copied out of the systemd credential into
`/var/lib/llama-server-rocm/api-key` and passed as `--api-key-file`. It starts by hand: the router
loads nothing until a request names a preset, and it is the fastest engine when a request does arrive.
`llama-logs` boots with the boot engine and follows every engine's journal, and gufo-auth's.

Memory here is one pool the iGPU shares, so read it from `/sys/class/drm/card1/device/mem_info_gtt_used`
rather than `btop`: the weights are GTT buffer objects allocated kernel-side, invisible to every process
RSS and to every cgroup (89 GiB of GTT against 6 GiB of `gufo` RSS), `MemAvailable` counts GTT pages that
cannot be reclaimed, and `MemoryMax=` on the unit can only bound the host-side half. A load that finds GTT
still held by a SIGKILLed predecessor puts the weights in host anonymous memory instead - 85 GiB of RSS,
then tens of GiB squeezed into zram, then a *global* OOM kill - which is what `TimeoutStopSec` and
`RestartSec` on the unit are for, together with `vm.min_free_kbytes` and the 10% zram in
`nixos/hardware.nix`. Its input tracks `main`, so before activating a bumped version measure
decode at 150k+ tokens: 0.17.0 plus PR #626 cut attention cost in gufo's own benchmarks but dropped
long-context decode to single digits on this box.

**The CI runner is on this box, so a global OOM takes a CI job with it.** On 2026-10-20 01:00 the
kernel's OOM killer went through the process table and the Forgejo Actions job died as collateral:
its nix build was SIGKILLed (exit 137) and the run went red for a reason that is nowhere in the
job's log. The workflows cache the nix store (`actions/cache` on `/nix`), which is what keeps a job
from building the toolchain at all - a cold store is the memory spike that tips a loaded box over.

## The CI runner

`nixos/services/ci-runner.nix` runs the Forgejo Actions runner as `forgejo-runner-framework.service`
(the unit name is fixed by nixpkgs' `services.forgejo-runner`; nixpkgs refuses to run forgejo-runner
through the old `services.gitea-actions-runner`, so that module breaks the build). Its state lives in
`/var/lib/ci-runner/framework` and the token is `secrets/ci-runner-token`, handed over as a systemd
credential. The runner's **uuid** is in the nix file rather than in `secrets/`: it is an identifier, not
a credential - but the two go together, so re-creating the runner in the WebUI means replacing the uuid
*and* the token. The `framework:` label is what routes a job to this box, and the label set is what the
server matches on, so changing it means re-registering.

## Restarting by hand instead of rebuilding

`llama-server-vulkan` after editing `/home/LLMs/llama-server.ini`, `llama-server-rocm` after editing
`/home/LLMs/llama-server-rocm.ini` (the compose copy comes from the store, so that one needs a
rebuild), `adguardhome` to force a filter-list update (the merge drops `last_updated`, so the lists
re-download), `gufo-auth` after rotating the API key (only the front door re-reads it, so gufo
keeps its weights loaded), `crucible` for the same rotation (it reads the key once at start), and the
cloudflared tunnels when the boot-minute DNS race got them.
`llama-rocm-image-update` rebuilds the container image, reloads it into `llm`'s daemon, and then
`llama-server-rocm` needs a restart to run it. `home-manager/pi/subagents.json` and `models.json` are
read at pi's startup, so they need `nh os switch` *and* a pi restart. There is no `nh home switch`
here: home-manager is a NixOS module of this flake, which exports no `homeConfigurations`.

## Couplings that break quietly

- **The `hosts` entries in `nixos/services/adguardhome.nix`** are what keep `steelph0enix.framework`,
  `search.framework` and `steelph0enix.pc` resolvable. `models.json` and `SEARXNG_URL` name those
  hosts, so moving or renaming a box breaks pi on both — and it breaks *only* the things that resolve,
  because DNS for everything else is AdGuard on `192.168.0.185`. When that box is down, this one loses
  its default provider and every lookup that isn't one of those rewrites. The `resolvconf` options there
  (`timeout:2 attempts:3 single-request-reopen`) are a mitigation for AdGuard dropping about one UDP
  reply in twenty, and at glibc's defaults a lost reply costs five seconds; don't remove them as noise.
- **Ports.** `nix/settings/host.nix` (composed by `nix/settings.nix`) holds `llmPort` and
  `llamaLogsPort`, and `nixos/services.nix` opens them; there is no separate firewall file to remember. Every inference engine binds `llmPort`
  and the units conflict, so only one listener is ever on it. The log viewer binds every interface
  (`server.py --host` defaults to the IPv4 wildcard address), so 51580 is what makes it reachable; if
  you open something, check what it actually binds (`ss -tulpn`). XRDP is off by default
  (`settings.enableRdp`); lightdm is not installed, so an RDP session is xrdp's own Xorg plus
  `xfce4-session`.
- **The presets are `/home/LLMs/llama-server.ini` and `/home/LLMs/llama-server-rocm.ini`, and the
  checkout only symlinks them.** A rebuild never deploys edits to them, so edit the file and restart
  the owning unit. The weights sit on the filesystem mounted at `/home`
  (`nixos/hardware-configuration.nix`), so a layout change takes the servers with it.
- **tuned owns the CPU side.** It runs with `ppdSupport = false`, so `powerManagement.cpuFreqGovernor`
  and any hand-rolled governor would fight it; the same goes for audio power saving, which tuned
  disables and the kernel parameter repeats.
- **`nix/nixpkgs-config.nix` here is only `allowUnfree`.** There is no `badpkgs`
  list and no download-verification overrides, unlike the other branch — a package that needs an
  override over there may build plainly here, and backporting an override that references `badpkgs`
  fails to evaluate here.

## The subagent fleet lives here

Most subagents run on this box's server (provider `llama-pc`), through the `pc` group, which allows one
model at a time. So a live test of an extension, or a big model swap, is felt on the other machine too,
and a model left loaded blocks the fleet. The `-smart` trio (`coder-smart`, `reviewer-smart`,
`assistant-smart`) is the exception: it runs on the framework box's boot engine, the model the main
session itself uses (provider `framework`), through the `framework` group, also one model at a time.
That engine serves two 262k slots (`settings.crucibleStreams`), so one `-smart` task can sit beside
the main session instead of queueing behind it; `subagents.json`'s 1 slot still serializes the
trio behind each other: one task at a time, the slowest and the most capable thing here.
`framework` endpoint is Crucible serving `Qwen 3.8 Flash Next` - the name it serves under exactly; the
llama.cpp preset catalog, or gufo's one slot, is the answer only once another engine has been started
by hand on top of it.

`models.json` pins `Qwen 3.8 Flash Next` at `contextWindow: 262144`, the one hand-written window in the
catalog: neither Crucible nor gufo reports an `n_ctx` in `/models`, so `llama-compat` has nothing to
read for it and would otherwise fall back to pi's 128K default. Both client catalogs also carry
`compat` overrides for that entry, because Crucible refuses request fields outside its allow list:
`supportsStore` and (for pi) `supportsDeveloperRole` off, and omp's thinking routed through
`chat_template_kwargs` (`thinkingFormat: qwen-chat-template`) instead of a top-level
`preserve_thinking`.

Before testing:

- name an explicit instance instead of the default (`framework` is the framework box's gufo endpoint
  and pi's default provider — that's the session someone is working in), e.g.
  `--provider llama-pc --model qwen-27B`;
- check what's resident and what's queued before loading anything:
  `curl -s http://steelph0enix.pc:51536/slots`;
- expect a reload of several GB when the model you want isn't the one loaded — `--models-max 1`.

## pi extensions

`home-manager/pi/extensions/<name>/` ships a `README.md` (what it is, its configuration, its commands,
setup gotchas) and an `AGENTS.md` (internals, invariants, tests). Keep that split when editing them —
a README stays free of source-file references and implementation detail. Run the scripts from inside
the extension's own directory:

- `subagents/`: `node test-utils/check.mjs` — about a second, no pi running, no model called.
- `compact-delegate/`: `node test-utils/check.mjs` — offline; its `AGENTS.md` has the way to force a real
  compaction in an isolated agent dir without touching the live one.
- `llama-dx/`: `preview.mjs --check` for the layout, `check.mjs` for everything else, `harness.mjs`
  for one real request; `TESTING.md` has the commands and the `tsc` invocation.
- A live test never runs on pi's default model (provider `framework` on this box): that is the
  instance serving whoever is doing the work, and the request eats its KV cache. Name the testing
  instance — `--provider llama-pc --model qwen-27B`.

## Where a change goes

A new service is a file in `nixos/services/` imported from `nixos/services/default.nix` — note that
`./services` in an import resolves to `nixos/services.nix`, so the directory entry has to be named
explicitly, as `configuration.nix` already does. Its port goes in `nix/settings/host.nix` and
`nixos/networking.nix` together; its credentials come from `secrets/` as a systemd credential or env
file. What only the user needs goes in `home-manager/packages.nix`; `nixos/packages/` holds what the
system itself needs (split `dev` / `media` / `system`). Identity — user, host, paths — is read from
`nix/settings/` rather than repeated anywhere else.

## pi's colours

`home-manager/pi/themes/noctalia.json` installs to `~/.pi/agent/themes/noctalia.json` and is the
source on this machine: on the other box that file is generated from the live Noctalia palette, and
this copy — carried over from there — keeps the two machines identical. Edit the repo copy and
re-activate, never the installed one. An installed file that home-manager does not own gets renamed to
`noctalia.json.hmgr.backup` on the first activation, which is expected once.
