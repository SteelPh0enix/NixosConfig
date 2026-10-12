# nixos-config

NixOS configuration for `RX-78-FPC` — a Framework desktop (AMD Zen 5, Vulkan and ROCm) that is the
daily driver, the LAN's DNS / ad-blocking / media box, and a local LLM host. One flake, one host:
`192.168.0.185`, `steelph0enix.framework`. The other box on the LAN, `steelph0enix.pc`, has its own
checkout.

## Layout

| path | what lives there |
|---|---|
| `nix/settings.nix` | identity and shared paths — `userName`, `hostId`, the llama.cpp paths and ports. Every module gets it as `settings` |
| `nix/` | overlays, the dev-tool list shared by the system and the editors, nixpkgs config |
| `nixos/` | the system: boot and kernel, hardware tuning, networking and firewall, users, packages, services |
| `nixos/services/` | one file per service; a service needing extra files (the llama-server preset, the log viewer) gets a directory |
| `home-manager/` | the user: fish and its scripts, packages, fonts, nixvim, pi |
| `secrets/` | secrets read by services — gitignored, mode 0700, never in the store |
| `.pi/` | pi's local state in this checkout (saved subagent sessions), gitignored |

## Rebuild

`programs.nh.flake` points `nh` at this repo, so no path is needed. `nh` reads the host from
`networking.hostName` and refuses to build on a mismatch.

```bash
nh os switch                    # build and activate
nh os boot                      # build and make it the default boot entry; switch on reboot
nh home switch                  # home-manager only
```

The runs that are more than one command are installed as wrapper scripts by `home-manager/shell.nix`:

| script | does |
|---|---|
| `os-rebuild` · `os-rebuild-switch` | `nh os boot` · `nh os switch`, both with `--keep-going` |
| `os-update` | pull `~/llama.cpp`, restart `adguardhome` so the merged filter lists re-apply, then `nh os boot --refresh --commit-lock-file --update` |
| `os-repair` | `nh os boot --repair --install-bootloader` |
| `os-clean` · `os-check` | `nh clean all` · `nix-store --verify --check-contents --repair` |

Garbage collection runs daily through `nh.clean`.

## What runs

Nothing is port-forwarded on the router; the two public hosts are tunnels that dial out to
Cloudflare. "LAN" below means `192.168.0.0/24`, plus the tailnet.

| service | port | reach |
|---|---|---|
| AdGuard Home | 53 DNS, 8123 UI | LAN — the service opens only the UI, `nixos/networking.nix` opens 53 |
| Forgejo + actions runner | 6969 HTTP, 22137 SSH | LAN |
| Jellyfin | 8096 | LAN |
| qBittorrent · Jackett · FlaResolverr | 8888 · 8889 · 8890 | LAN |
| SearXNG | 7777 | LAN, and `search.steelph0enix.dev` through the tunnel |
| llama.cpp server (Vulkan) | 51536 | LAN |
| its log viewer | 51580 | LAN |
| llama.cpp server (ROCm, rootless Docker) | 33333 | LAN, and `clanker.steelph0enix.dev` through the tunnel, behind an API key |
| nginx vhosts | 6970 coverage reports, 6971 docs | LAN |
| Samba + wsdd | 137–139, 445 | LAN only (`hosts allow`) |
| XRDP | 3389 | LAN |
| Tailscale | UDP 41641 | tailnet; subnet router and exit node |
| Minecraft (Create+) | 25565 | disabled |

## The LLM stack

Two OpenAI-compatible llama.cpp servers answer on this box.

- **51536** — the Vulkan server. Its presets are listed in `llama-server.ini`: one loads on the first
  request that names it, and up to four stay resident.
- **33333** — a ROCm server run by rootless Docker Compose out of `~/LLMs/`, which is also what
  `clanker.steelph0enix.dev` reaches.

Weights and the preset sit under `/home/LLMs`, outside the repo. Editing a preset is an edit plus a
service restart, never a rebuild; `AGENTS.md` has the details. SearXNG on 7777 is the instance pi's
web search talks to.

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

Its colours come from `themes/noctalia.json`, kept here so this machine and the other one colour pi the
same way.

## Outside this repo

Three flake inputs are `path:` checkouts living elsewhere, not managed by this flake's git:

| input | path | refresh |
|---|---|---|
| `llama-cpp` | `~/llama.cpp` | `llama-cpp-update` pulls it; `nix flake update llama-cpp` is a no-op because the working tree *is* the input |
| `mcserver` | `~/Projects/mcserver-nix` | `nix flake update mcserver` after the pack is regenerated there |
| `berkeleyMono` | `~/nixos-nonfree/berkeley-mono` | licensed, non-redistributable TTFs, mode 700 |

## secrets/

Gitignored as a whole, and copied in by hand at mode 0600 when a machine is new — nothing fetches
them. Each is read by path, as a boot-time credential or an env file.

| file | read by |
|---|---|
| `cloudflare-clanker-credentials.json` | cloudflared, the `clanker` tunnel |
| `cloudflare-search-credentials.json` | cloudflared, the `search` tunnel |
| `tailscale-authkey` | tailscaled, re-applied on every boot |
| `searxng.env` | SearXNG (`SEARXNG_SECRET`, optional Brave/Kagi keys) |
| `llama-strix-api-key` | the ROCm server, through `~/LLMs/.env`, and pi's `models.json` through an `apiKey: "!command"` |

## Notes

`kernel-version-pin.md` is a runbook from the 2026-10 kernel breakage: how to find the revision that
produces the running kernel, pin it, prove the pin worked, and unpin it.
