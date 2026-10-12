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
  (see the README); and the kernel comes from `nix-cachyos-kernel`. If a kernel must be frozen, the
  pin goes in `flake.nix` with the reasoning, not quietly in `flake.lock` — `kernel-version-pin.md`.
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

Weights and the preset live in `/home/LLMs` for that reason: the unit runs as `llama` and cannot
traverse a 0700 home. The checkout keeps a **symlink** to `llama-server.ini`, so editing presets is an
edit plus a restart of the unit, and no rebuild.

The one on **33333** is not a NixOS unit at all: rootless Docker Compose from
`~/LLMs/llm-router-docker-compose.yml`, key in `~/LLMs/.env` (`STRIX_API_KEY`). Nothing in this repo
rebuilds it, and `nix` changes never touch it.

## Restarting by hand instead of rebuilding

`llama-server-vulkan` after editing `/home/LLMs/llama-server.ini`, `adguardhome` to force a filter-list
update (the merge drops `last_updated`, so the lists re-download), and the cloudflared tunnels when the
boot-minute DNS race got them. `home-manager/pi/subagents.json` and `models.json` are read at pi's
startup, so they need `nh os switch` *and* a pi restart. There is no `nh home switch` here: home-manager is a NixOS
module of this flake, which exports no `homeConfigurations`.

## Couplings that break quietly

- **Ports.** Services bind `0.0.0.0` and the firewall decides. `nix/settings.nix` holds the numbers,
  `nixos/networking.nix` opens them, and AdGuard's 53 is opened there rather than by the service.
  Change one side and the other drifts.
- **DNS ordering.** Most services wait on `dns-ready.target`, whose probe asks AdGuard on loopback and
  insists on a real answer, because AdGuard serves its startup rewrites even with dead upstreams. Do
  not bypass the target to make a service start sooner.
- **cloudflared.** Ingress is declared in Nix precisely so it survives a rebuild. A public-hostname
  route added in the Zero Trust dashboard makes cloudflared fetch remote config and silently ignore
  the ingress in this repo.
- **Samba** comes from `nixpkgs-previous` because current nixpkgs samba does not build.
- **AdGuard config** is authoritative from Nix: a `preStart` merges the generated yaml into
  `/var/lib/AdGuardHome`, so UI-only changes survive and upstreams, filters and rewrites do not.

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
