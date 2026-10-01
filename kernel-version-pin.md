# Locking the kernel to a specific version (and proving it worked)

Written after the 2026-10-01 breakage: `nh os boot` started rebuilding
`linux-cachyos-latest-lto-x86_64-v3` locally (no substitute) and the build died in
`tools/bpf/resolve_btfids` (`ld.lld: error: undefined symbol`, referenced by `btf_relocate.c`).
The kernel is now frozen at the revision that produces the running kernel, so updates stop
rebuilding it.

## 1. Know what you are running

```bash
uname -r                                     # 7.2.8-cachyos-lto
readlink -f /run/booted-system/kernel        # /nix/store/kxs8q…-linux-cachyos-latest-lto-x86_64-v3-7.2.8/bzImage
readlink -f /run/current-system/kernel       # same, for the *configured* system (may be newer than booted)
nix-store --query --deriver <kernel-store-path>   # "unknown-deriver" => it was substituted, not built here
```

The store path in that symlink is the thing to keep. If a "freeze" ends up with a *different*
store path, it is a rebuild, no matter what the version string says.

## 2. Find which input produced that store path

`nix-cachyos-kernel` is the kernel source here (`nixos/boot.nix` → `pkgs.cachyosKernels`
→ `inputs.nix-cachyos-kernel.overlays.pinned`). Walk the lockfile history and evaluate the
candidates — evaluation is cheap, nothing gets built:

```bash
git log -p -- flake.lock | grep -E 'nix-cachyos-kernel|rev'   # or: git show <c>:flake.lock
cat > /tmp/probe.nix <<'EOF'
let
  kernFlake = builtins.getFlake "github:xddxdd/nix-cachyos-kernel/b1332396df6e880d7e3b6b451c6a74132ce8cf66";
  pkgs = import (builtins.getFlake "github:NixOS/nixpkgs/7a0f122f5090cf4c2ade2a13a0e229d4e19ba71f").sourceInfo.outPath {
    system = "x86_64-linux";
    config = { allowUnfree = true; rocmSupport = true; };
    overlays = [ kernFlake.overlays.pinned ];
  };
in pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v3.kernel.outPath
EOF
nix eval --raw -f /tmp/probe.nix    # want exactly the path from step 1
```

That printed `kxs8qcaf100xpklda6qwrsv0yvbqsp0g-…` on the first try: the running kernel comes
from `nix-cachyos-kernel@b1332396df6e`.

**Key detail:** `overlays.pinned` maps `cachyosKernels` to *the kernel flake's own*
`legacyPackages`, i.e. its own locked nixpkgs. Verified by evaluating the same expression
against two different host nixpkgs revisions — same output path both times. So the host
`nixpkgs` input is irrelevant for this kernel and **one pinned input is enough**. Had the
kernel come from the host package set, the `nixpkgs` bump (gcc 15.3 → 16.2, pahole, stdenv)
would have to be pinned too — see "Variants".

## 3. Pin it in `flake.nix`, not in `flake.lock`

```nix
# Pinned: newer revisions build their kernel against a nixpkgs whose lld cannot link
# tools/bpf/resolve_btfids, and the resulting derivation has no cached build (the overlay
# is self-contained, so this rev alone fixes the kernel store path). Unpin once upstream
# builds again; the running kernel is 7.2.8-cachyos-lto.
nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/b1332396df6e880d7e3b6b451c6a74132ce8cf66";
```

A commit in the input URL is used as `ref`, so `nix flake update` re-resolves it to itself.
Editing only `flake.lock` would be thrown away by the next `nh os update` — same trick as the
existing `nixpkgs-previous` samba pin, which has survived dozens of lockfile updates.

Then relock and commit:

```bash
nix flake update nix-cachyos-kernel   # moves only that node (and its own nixpkgs node)
git add flake.lock flake.nix
```

Note: any *new* file referenced by the config must be `git add`-ed, or the build fails with
`Path '…' in the repository … is not tracked by Git` (the flake builds from the committed tree).

## 4. Verify

```bash
# a) the system resolves the kernel to the already-installed path
nix eval --raw .#nixosConfigurations.RX-78-FPC.config.boot.kernelPackages.kernel.outPath
#    => /nix/store/kxs8qcaf100xpklda6qwrsv0yvbqsp0g-linux-cachyos-latest-lto-x86_64-v3-7.2.8

# b) the whole system builds, and the kernel is not in the build log
nix build --no-link --keep-going -L .#nixosConfigurations.RX-78-FPC.config.system.build.toplevel
nix eval --raw .#nixosConfigurations.RX-78-FPC.config.system.build.toplevel.outPath \
  | xargs -I{} readlink -f {}/kernel        # still kxs8q…

# c) the freeze survives a full update (what `nh os update` runs)
cp flake.lock /tmp/flake.lock.bak
nix flake update
nix eval --raw .#nixosConfigurations.RX-78-FPC.config.boot.kernelPackages.kernel.outPath
# unchanged => pin holds; keep the new lock, or restore /tmp/flake.lock.bak

# d) when a rebuild is unexpected, diff the two derivations to see what moved
nix derivation show /nix/store/<old>.drv > /tmp/old.json
nix derivation show /nix/store/<new>.drv > /tmp/new.json
nix log /nix/store/<failed>.drv          # full build log of the failing package
```

In (c) the full update moved nothing, and (b) needed no kernel build — the long local LTO
compile is gone, `nh os boot` now only builds the small userspace diffs.

## 5. Testing a newer kernel without unpinning

`--override-input` is per-invocation, the lockfile stays pinned:

```bash
nix build --no-link -L --override-input nix-cachyos-kernel github:xddxdd/nix-cachyos-kernel/<newrev> \
  .#nixosConfigurations.RX-78-FPC.config.system.build.toplevel
```

If it builds, drop the rev from the URL in `flake.nix` and `nix flake update nix-cachyos-kernel`.

## Variants

- **Kernel from the host nixpkgs** (e.g. `linuxPackages_zen`, `linuxPackages_latest`): pin a
  second nixpkgs input and take the whole package set from it, so the derivation stays
  byte-identical while the rest of the system moves:

  ```nix
  inputs.nixpkgs-kernel.url = "github:NixOS/nixpkgs/<rev>";

  boot.kernelPackages =
    (import inputs.nixpkgs-kernel {
      system = pkgs.stdenv.hostPlatform.system;
      config = import ../nix/nixpkgs-config.nix;
      overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
    }).linuxPackages-cachyos-latest-lto-x86_64-v3;
  ```

  Everything out-of-tree (NVIDIA, ZFS, `boot.extraModulePackages`) then builds against the
  pinned kernel, since NixOS reads them from `boot.kernelPackages`.

- **`overrideAttrs` / `linuxPackagesFor`**: only useful for changing flags or patches — the
  version still comes from the package source, and it will still rebuild.

- **Importing the old `.drv`** (`import /nix/store/<hash>-linux-….drv`): yields the exact old
  outputs but breaks as soon as that `.drv` is garbage-collected, and no substitute is
  reachable for it. Don't.

## Costs

A frozen kernel gets no security fixes and no new drivers while pinned, and it drifts from the
`nixpkgs` the rest of the system comes from (out-of-tree modules, `nvidiaPackages`, etc.). Keep
the pin short-lived: leave the comment in `flake.nix`, retry with `--override-input` after
upstream moves.
