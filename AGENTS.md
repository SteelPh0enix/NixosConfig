# Working in this repo

Rules and traps for changing the `main-pc` branch of `~/nixos-config`. `README.md` says what this
machine is and runs; read that first if it isn't obvious yet.

## One branch, one machine, two checkout

This flake builds `steelph0enix-pc` and nothing else. `framework-pc` is the other branch, for
`RX-78-FPC`, and the two have diverged (547 commits here that aren't there, 988 there that aren't
here): never assume a file, an option or a comment means the same thing on both. Share something by
cherry-picking it deliberately — `home-manager/pi/` is the one part that is kept identical.

The box runs its own checkout at `~/nixos-config` on this branch, and it is not always in step with
`origin/main-pc` (right now three `flake.lock` commits sit unpushed there). So: change and commit
here, push, pull there. Editing that tree by hand gets overwritten by the next activation. Also,
`/etc/nixos` on that box is a leftover stock `configuration.nix` from the install — it is not the
config, and `nh` never reads it.

## Checking a change

A plain eval of this branch fails on the framework box, because `flake.lock` pins `llama-cpp` as a
`path:` input with the hash of *that* machine's `~/llama.cpp`:

```
error: NAR hash mismatch in input 'path:/home/steelph0enix/llama.cpp?...', expected ..., but got ...
```

Overriding the input rescues evaluation, and those two commands are what actually work from either
box:

```bash
nix eval --raw --override-input llama-cpp "path:$HOME/llama.cpp" \
  .#nixosConfigurations.steelph0enix-pc.config.networking.hostName
nix eval --override-input llama-cpp "path:$HOME/llama.cpp" \
  .#nixosConfigurations.steelph0enix-pc.config.systemd.services.llama-server-vulkan.serviceConfig.Restart
```

```bash
nh os switch        # build the system and activate it now, home-manager files included
nh os boot          # build it and make it the default boot entry; apply on reboot
# no `nh home switch`: home-manager is a NixOS module of this flake, which exports no
# homeConfigurations - a user-side change goes out with `nh os switch` too

nix build .#nixosConfigurations.steelph0enix-pc.config.system.build.toplevel --no-link  # heavy
```

That build only means anything on the machine itself: the `path:` inputs are different trees per box,
and the preset this server needs lives on its disk. `nix flake check` drags the whole system config
along and stops on any input that no longer evaluates.

Format `.nix` with `nixfmt`, lint with `statix` and `deadnix`, `shellcheck` the scripts in
`home-manager/shell.nix` — all in `nix develop`. `nixfmt` reports one difference in
`home-manager/pi/default.nix` that predates this way of writing (a long `entryAfter` line); leave it
rather than reflow a file you barely touched. Keep the surrounding style: options in alphabetical-ish
groups, and comments that say *why*, since almost every odd value here is a workaround for something.

## Do not

- **Read, print or copy anything in `secrets/`,** and never inline a secret in a `.nix`. On this box
  the dir holds one file, `llama-strix-api-key`; the framework branch's cloudflared, tailscale and
  searxng secrets are not needed here and copying them over achieves nothing.
- Hand-edit `~/.pi/agent/`. `models.json`, `subagents.json`, `APPEND_SYSTEM.md`, `prompts/` and the
  extensions are home-manager symlinks into the store; edit the repo and re-activate. Only
  `settings.json`, `auth.json`, `trust.json` and `sessions/` belong to pi, and `settings.json` gets the
  managed keys merged over it by an activation script, so a hand-edit of a managed key is shadowed
  anyway. (`models.json.hmgr.backup` there is the pre-`!command` copy kept by that merge, not
  something to restore.)
- Hand-edit `~/.pi/agent/themes/noctalia.json`. Noctalia's `pi-agent` template regenerates it from the
  live palette; a hand-edit disappears. If the palette really changed, regenerate it and refresh the
  copy the framework branch carries, so the two machines don't drift apart.
- Run `nix flake update` casually. `pi` has no binary cache, so it costs minutes of local building,
  and `llama-cpp` and `berkeleyMono` are `path:` inputs where an update does nothing.
- Trust a fact about the LLM stack learned on the other machine. `--models-max 1` here against 4
  there, per-preset `--parallel`, and `models.json` has the providers pointing at the same hosts in
  both directions but from opposite ends.

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
- **The palette include in `home-manager/niri/config.kdl`.** Noctalia's `niri` template writes
  `~/.config/niri/noctalia.kdl` and greps the config for an include line before wiring it up; the
  config here is a store symlink, so dropping `include optional=true "noctalia.kdl"` makes the
  template try to append to a read-only file and the colours never reach the compositor.

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
setup gotchas) and an `AGENTS.md` (internals, invariants, tests); their code is identical to the other
branch, and the docs are kept identical too. Run the scripts from inside the extension's own
directory:

- `subagents/`: `node test-utils/check.mjs` — about a second, no pi running, no model called.
- `compact-delegate/`: `node test-utils/check.mjs` — offline; its `AGENTS.md` has the way to force a real
  compaction in an isolated agent dir without touching the live one.
- `llama-dx/`: `preview.mjs --check` for the layout, `check.mjs` for everything else, `harness.mjs`
  for one real request; `TESTING.md` has the commands and the `tsc` invocation.

## Where a change goes

A new service is a file in `nixos/services/` listed in `nixos/services/default.nix` — but note that
the network on this branch lives in `nixos/services.nix`, not a `nixos/networking.nix`, so firewall,
`hosts` and ssh options are edited there. What only the user needs goes in `home-manager/packages.nix`;
`nixos/packages/` is for the system. The desktop has two halves: `nixos/desktop.nix` (niri, greetd
and the Noctalia greeter, keyring, UPower) and the user side — `home-manager/niri/` for the
compositor config, `home-manager/noctalia.nix` (whose theme templates generate things like pi's
theme) and `home-manager/phonto.nix` for the shell and the wallpaper. Identity — user, host, ports,
paths — comes from `nix/settings.nix` and is never repeated.

## Noise worth knowing

- The Mesa **DZN** ICD fails to initialise (`vkCreateInstance` → -9) and gets skipped. RADV is the
  driver and `Vulkan0`; leave it alone.
- `.gitignore` carries `smb-secrets`, which nothing on this branch reads — Samba is on the framework
  box.
- docker is installed with the user in the group and runs nothing; no container here serves any port.
- `freecad` is commented out in `home-manager/packages.nix` on purpose.
