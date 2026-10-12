# nixos-config

The `main-pc` branch: NixOS and home-manager for `steelph0enix-pc` (`192.168.0.150`, the name
`steelph0enix.pc` on the LAN) — a self-built desktop, Ryzen 9 5900X (Zen 3: AVX2, no AVX-512) with a
Radeon RX 7900 XT driven by RADV, 31 GiB RAM, zram instead of a swap partition, ext4 root plus three
extra drives mounted under `/mnt`. It is the household's small-model host: the llama.cpp server on
this box serves the subagents of *both* machines.

The other branch, `framework-pc`, builds `RX-78-FPC` (`192.168.0.185`, `steelph0enix.framework`) —
the DNS and ad-blocking box, the ROCm host, the one with the tunnels. The two branches split long ago
and were never merged: 547 commits here are missing there, 988 there are missing here. The pi config
is the exception — it is kept identical on purpose.

## What comes from the other box

| thing | where it actually is |
|---|---|
| DNS, and the LAN names | AdGuard on `192.168.0.185`; `steelph0enix.framework` and `search.framework` are also written into `nixos/services.nix` as `hosts` entries, so they resolve even without it |
| pi's default provider `llama-main` | `steelph0enix.framework:33333` — the ROCm STRIX router there, API key read from `secrets/` at request time |
| `llama-fwpc-vulkan` | `steelph0enix.framework:51536` — that box's Vulkan server, empty until a preset is named |
| SearXNG for pi's web search | `search.framework:7777`, set as `SEARXNG_URL` |

What this box gives back: `llama-pc` (`steelph0enix.pc:51536`), the server every subagent — on either
machine — runs on.

## Layout

| path | what lives there |
|---|---|
| `nix/settings.nix` | identity and shared paths — user, host id, the llama.cpp paths and ports; every module receives it as `settings` |
| `nix/` | overlays (`llama-cpp`, `flashpoint`, `phonto`, `ltrace`, a rust toolchain), the shared dev-tool list, nixpkgs config |
| `nixos/` | boot and kernel, hardware, users, packages, services — and the network: unlike the other branch there is no `nixos/networking.nix`, the firewall and hosts entries live in `nixos/services.nix` |
| `nixos/services/` | only two modules, both for llama.cpp; everything else is a `services.*` option in `nixos/services.nix` |
| `nixos/hyprland.nix` | the system half of the desktop: greetd, pipewire, bluetooth, LACT, udev rules |
| `home-manager/` | the user: fish, packages, fonts, nixvim, `hyprland/` (Noctalia), theming, xdg, vesktop, flashpoint, pi |
| `secrets/` | gitignored, copied in by hand; on this box it holds one file (see below) |

## Rebuild

`nh` is pointed at this repo (`programs.nh.flake`), and it refuses to build for a host other than
`networking.hostName`. The box keeps its own checkout at `~/nixos-config`, on this branch.

```bash
nh os switch                    # build and activate
nh os boot                      # build and make it the default boot entry
nh home switch                  # home-manager only
```

`os-rebuild`, `os-rebuild-switch`, `os-update`, `os-repair`, `os-clean`, `os-check` wrap those with
`--keep-going`, `--refresh`, `--commit-lock-file` and friends; they are defined in
`home-manager/shell.nix`. `nh clean` runs daily as a timer.

## What runs

| service | port | reach |
|---|---|---|
| llama.cpp server (Vulkan, presets) | 51536 | LAN — the only thing opened for real |
| its log viewer | 51580 | loopback (a firewall rule exists, but the viewer binds `127.0.0.1`) |
| sshd | 22137 | LAN, keys only, `AllowUsers steelph0enix` |
| CUPS | 631 | loopback |
| avahi | 5353 | not opened, publishing off |

Nothing is port-forwarded on the router, there is no tunnel and no VPN here, and no DNS, search
engine, git host or media server — those are on the framework box. Also running, without a port:
tuned with its PPD profiles, ucodenix, fwupd, LACT, flatpak, docker (with nothing in it), and the
`nh-clean`, `fstrim`, `logrotate`, `fwupd-refresh` timers.

## The model host

`llama-server-vulkan` runs as the `llama` user with
`--host 0.0.0.0 --port 51536 --slots --props --metrics --models-max 1 --models-preset <file> --webui
--perf`, and `GGML_VK_VISIBLE_DEVICES=0` because llvmpipe turns up as a second Vulkan device.

The preset is `/mnt/NVMe/LLMs/llama-server.ini`. **It is not in this repo** — it is edited in place
and needs a unit restart, not a rebuild. Its five model sections are `qwen-27B`, `cyber-tiel-coder`,
`occult-nail`, `lfm` and `sharp-spark`; `--models-max 1` keeps exactly one resident, so a request for
another one pays a reload (the framework box keeps four). Each loaded model gets its own child server
on a loopback port, which is what `--slots` reports through 51536.

Serving is Vulkan only — no ROCm tooling is installed, and the ROCm router everyone associates with
the household is the Docker Compose stack on the framework box.

## Desktop

Hyprland under greetd, with Noctalia v5: the community *Cyberpunk* palette, the dock, DDC/CI
brightness, and `systemd.enable` so the session starts through systemd. wezterm is the terminal
(Noctalia colours, Berkeley Mono, 120x30), phonto paints a video wallpaper through a user unit that
stops after 15 minutes, and `home-manager/theming.nix` propagates the palette to the rest of the
user session. Hardware-specific pieces: LACT for the 7900 XT, a Coral Edge TPU udev rule, the Moondrop
Dawn Pro 2 audio device owned by the user, low-latency PipeWire (48 kHz, quantum 32) and the full
Bluetooth codec set. `amdgpu` gets `gpu_recovery`, `gfx_off=0`, `runpm=0` on the kernel command line,
and tuned keeps audio power saving off (the `snd-hda-intel.power_save=0` parameter is belt braces).

## pi

pi, the coding agent, is configured with the rest of the user config: `home-manager/pi/` holds its
settings, `models.json` (three llama.cpp providers: this box's two servers and the other machine's),
the prompt templates in `prompts/`, and its extensions — five directories, each documented as a
`README.md` for use and an `AGENTS.md` for its internals:

| extension | what it does |
|---|---|
| [`llama-compat`](home-manager/pi/extensions/llama-compat/README.md) | keeps pi's model catalog honest about what a server really serves |
| [`llama-dx`](home-manager/pi/extensions/llama-dx/README.md) | llama.cpp's diagnostics for the current request, in pi's footer |
| [`searxng`](home-manager/pi/extensions/searxng/README.md) | `web_search` against the SearXNG instance on this box |
| [`subagents`](home-manager/pi/extensions/subagents/README.md) | background subagents bound to named models, with concurrency limits |
| [`webfetch`](home-manager/pi/extensions/webfetch/README.md) | `web_fetch` and `web_interact` through a local Chromium |

Its colours are *generated*: Noctalia's community `pi-agent` template writes
`~/.pi/agent/themes/noctalia.json` from the live palette, which is why no theme file ships here. The
framework branch carries a copy of that generated file so both machines colour pi the same way — when
the palette changes here, that copy is what should be refreshed.

## Outside this repo

| input | path | note |
|---|---|---|
| `llama-cpp` | `~/llama.cpp` | each machine keeps its own checkout, so the two lock files disagree |
| `berkeleyMono` | `~/nixos-nonfree/berkeley-mono` | licensed TTFs, not redistributable |

`nix flake update llama-cpp` is a no-op: the working tree *is* the input. `os-update` pulls
`~/llama.cpp` first, then rebuilds.

## secrets/

One file on this box: `llama-strix-api-key`, read by `models.json` through
`apiKey: "!cat …/secrets/llama-strix-api-key"` for the ROCm router over on the framework box. A fresh
checkout of this branch needs exactly that one file, mode 0600.
