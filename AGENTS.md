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
  `llama-cpp`, `mcserver` and `berkeleyMono` are `path:` inputs where an update does nothing at all
  (see the README). The kernel is `linuxPackages_xanmod_latest` from cache.nixos.org, so a `nixpkgs`
  bump normally just substitutes it; the `nix-cachyos-kernel` flake is gone because its author's
  cache and Hydra were compromised. If a kernel must be frozen, the pin goes in `flake.nix` with the
  reasoning, not quietly in `flake.lock`. `gufo` has no cache either, so it is the expensive input.
- Hand-edit `~/.pi/agent/settings.json` to change a managed setting. Edit `home-manager/pi/default.nix`
  and re-activate; a hand-edit in the live file only gets shadowed by the managed key again.

## The llama.cpp servers

The one on **51536** is a NixOS unit (`llama-server-vulkan`), built from the `llama-cpp` flake input
by `nix/overlays/llama-cpp.nix` — Vulkan only, `-march=znver5` (x86-64-v4 is not enough for the
AVX512 extensions here), LTO — running as the `llama` user with
`--slots --props --metrics --models-max 4 --webui`. Keep autoload on: with it off the server answers
`400 "model is not loaded"` instead of loading a named preset. Its process is sandboxed
(`ProtectSystem=strict`, `ProtectHome=read-only`, `LimitMEMLOCK=infinity`, `MemoryDenyWriteExecute`
off for the Vulkan JIT, `GGML_VK_VISIBLE_DEVICES=0` because llvmpipe shows up as a second device).
It no longer starts at boot: gufo's two 262144-token sessions fill the unified memory pool, so a model
loaded here on top would OOM the box. Start it (and `llama-vulkan-logs`) by hand when needed.

Weights and the preset live in `/home/LLMs` for that reason: the unit runs as `llama` and cannot
traverse a 0700 home. The checkout keeps a **symlink** to `llama-server.ini`, so editing presets is an
edit plus a restart of the unit, and no rebuild.

The one on **33333** is a NixOS unit: Gufo (`nixos/services/gufo.nix`) built from the `gufo` flake
input, serving Qwen3.8-Flash-Next with its shared MTP sidecar. It replaced the rootless-Docker
llama.cpp router, whose Compose/INI in `~/LLMs/` is kept only as manual rollback. Gufo has no binary
cache, so a `gufo` bump is a long local build. The API key is `secrets/llama-strix-api-key` (the
retired `.env` kept it as `STRIX_API_KEY`); gufo takes it only as `--api-key`, so it is visible in
the process command line and there is no env or file alternative. Its continuation cache is capped
with `--cache-ram-bytes` (the automatic budget is half of `MemAvailable` and throws the host into
swap), and `--stall-timeout-ms` exits a generation that stops progressing as `device_lost` so
systemd restarts the engine. Its input tracks `main`, so before activating a bumped version measure
decode at 150k+ tokens: 0.17.0 plus PR #626 cut attention cost in gufo's own benchmarks but dropped
long-context decode to single digits on this box.

## Restarting by hand instead of rebuilding

`llama-server-vulkan` after editing `/home/LLMs/llama-server.ini`, `adguardhome` to force a filter-list
update (the merge drops `last_updated`, so the lists re-download), and the cloudflared tunnels when the
boot-minute DNS race got them. `home-manager/pi/subagents.json` and `models.json` are read at pi's
startup, so they need `nh os switch` *and* a pi restart. There is no `nh home switch` here: home-manager is a NixOS
module of this flake, which exports no `homeConfigurations`.

## Couplings that break quietly

- **The `hosts` entries in `nixos/services.nix`** are what keep `steelph0enix.framework`,
  `search.framework` and `steelph0enix.pc` resolvable. `models.json` and `SEARXNG_URL` name those
  hosts, so moving or renaming a box breaks pi on both — and it breaks *only* the things that resolve,
  because DNS for everything else is AdGuard on `192.168.0.185`. When that box is down, this one loses
  its default provider and every lookup that isn't in `hosts`. The `resolvconf` options there
  (`timeout:2 attempts:3 single-request-reopen`) are a mitigation for AdGuard dropping about one UDP
  reply in twenty, and at glibc's defaults a lost reply costs five seconds; don't remove them as noise.
- **Ports.** `nix/settings.nix` holds `llamaRouterPort` and `llamaLogsPort`, and `nixos/services.nix`
  opens them; there is no separate firewall file to remember. The opened 51580 is currently pointless
  because the log viewer binds `127.0.0.1` — if you open something, check what it actually binds
  (`ss -tulpn`).
- **The preset is `/mnt/NVMe/LLMs/llama-server.ini`, untracked.** A rebuild never deploys edits to it,
  and a change to the disk layout takes the server with it. `nixos/hardware-configuration.nix` is
  where those `/mnt` mounts come from.
- **tuned owns the CPU side.** It is enabled with `ppdSupport`, so `powerManagement.cpuFreqGovernor`
  and any hand-rolled governor would fight it; the same goes for audio power saving, which tuned
  disables and the kernel parameter repeats.
- **`nix/nixpkgs-config.nix` here is only `allowUnfree` and `rocmSupport`.** There is no `badpkgs`
  list and no download-verification overrides, unlike the other branch — a package that needs an
  override over there may build plainly here, and backporting an override that references `badpkgs`
  fails to evaluate here.

## The subagent fleet lives here

Most subagents run on this box's server (provider `llama-pc`), through the `pc` group, which allows one
model at a time. So a live test of an extension, or a big model swap, is felt on the other machine too,
and a model left loaded blocks the fleet. The `-smart` trio (`coder-smart`, `reviewer-smart`,
`assistant-smart`) is the exception: it runs on the framework box's gufo server, the model the main
session itself uses (provider `llama-main`), through the `framework` group, also one model at a time.
That server has 2 slots of 262k and the main agent permanently holds one, so `subagents.json` gives the
subagents 1 slot: one `-smart` task at a time, and it is the slowest and the most capable thing here.

`models.json` pins `Qwen 3.8 Flash Next` at `contextWindow: 262144`, the one hand-written window in the
catalog: gufo reports no `n_ctx` in `/models` and no launch args, so `llama-compat` has nothing to read
for it and would otherwise fall back to pi's 128K default.

Before testing:

- name an explicit instance instead of the default (`llama-main` is the framework box's ROCm router and
  pi's default provider — that's the session someone is working in), e.g.
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
- A live test never runs on pi's default model (provider `llama-main` on this box): that is the
  instance serving whoever is doing the work, and the request eats its KV cache. Name the testing
  instance — `--provider llama-pc --model qwen-27B`.

## Where a change goes

A new service is a file in `nixos/services/` imported from `nixos/services/default.nix` — note that
`./services` in an import resolves to `nixos/services.nix`, so the directory entry has to be named
explicitly, as `configuration.nix` already does. Its port goes in `nix/settings.nix` and
`nixos/networking.nix` together; its credentials come from `secrets/` as a systemd credential or env
file. What only the user needs goes in `home-manager/packages.nix`; `nixos/packages/` holds what the
system itself needs (split `dev` / `media` / `system`). Identity — user, host, paths — is read from
`nix/settings.nix` rather than repeated anywhere else.

## pi's colours

`home-manager/pi/themes/noctalia.json` installs to `~/.pi/agent/themes/noctalia.json` and is the
source on this machine: on the other box that file is generated from the live Noctalia palette, and
this copy — carried over from there — keeps the two machines identical. Edit the repo copy and
re-activate, never the installed one. An installed file that home-manager does not own gets renamed to
`noctalia.json.hmgr.backup` on the first activation, which is expected once.
