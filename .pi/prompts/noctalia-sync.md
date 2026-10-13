---
description: Sync Noctalia Settings-GUI overrides into the Nix config, then delete them from the state file
argument-hint: "[top-level keys...] [--all]"
---

# Sync Noctalia GUI overrides into Nix

Noctalia merges two layers: the declarative `~/.config/noctalia/config.toml` (symlinked by Home
Manager from `programs.noctalia.settings`) and `~/.local/state/noctalia/settings.toml`, which the
Settings GUI (SUPER+comma) writes and which **wins**. This runbook moves every GUI override into the
Nix config, proves the declarative layer produces the same effective config, then deletes the
migrated overrides so Nix is the single source of truth.

Arguments: `${@:-all drifted keys}` — optional space-separated top-level keys to restrict the sync
to (e.g. `theme shell`); `--all` also handles the ASK list below.

## Hard rules

- Work top-down in this exact order. Never delete an override before the rebuild proves the
  declarative layer reproduces it — otherwise the running shell silently reverts to defaults.
- Never migrate, report instead: `config_version` (Noctalia's own migration stamp, must stay);
  any key matching `key|token|password|secret|credential` (secrets belong to agenix / Secret
  Service, never to the repo); identity and location data — `calendar.account.*` (account id, the
  token cached beside it), `location.address`; anything in `~/.local/state/noctalia/state.toml`
  (not part of this flow).
- A section that still holds a never-migrated key stays in the state file whole (`calendar`). Its
  migrated siblings then exist in both layers, which is harmless — never `del()` the private key alone.
- The GUI stores floats as float32, so the state file carries artifacts such as
  `corner_radius_scale = 0.70000001043081284`. Declare the clean decimal (`0.7`); that leaf then
  stays in every `comm` output as an accepted leftover and its section may still be deleted.
- **Cap anything that walks the config.** Recursion in a jq helper must descend `.value`, never the
  `{key,value}` entry a `map()` hands it — descend that and the tree doubles every level. A runaway
  does not die quietly either: this harness runs inside the Hyprland session cgroup
  (`wayland-wm@hyprland.desktop.service`), so the OOM killer looks for victims *there* and takes the
  desktop down (one bad `jq`: 28GB RSS, session killed, twice). Wrap it: `( ulimit -v 2000000; jq ... )`.
  A 6KB config needs a few MB. Better still, hand-write the Nix from the state file: the edit tool
  starts no process.
- ASK list, migrate only with `--all` or explicit confirmation: `lockscreen_widgets`,
  `desktop_widgets` — editor-generated per-output geometry (`cx`, `cy`, `box_*`, `placement_*`,
  `output`, `widget_order`) that is meaningless on other hardware. Both are declared here now, so
  they resurface as drift only when someone drags a widget in the editor.
- Ask before `nh os switch`; it restarts the shell session's bar and applies the *whole* working
  tree, so list the unrelated `git status` edits it would drag along (kernel params need a reboot).
  Never run it unattended.
- Close the Settings window first; it rewrites `settings.toml` on every change.

## 0. Setup

```bash
REPO=$HOME/nixos-config
MODULE=$REPO/home-manager/hyprland/noctalia.nix
STATE=$HOME/.local/state/noctalia/settings.toml
YQ="nix run nixpkgs#yq-go --"
export LC_ALL=C            # sort here and comm below must agree, or comm rejects its own input
W=$(mktemp -d); echo "$W" > /tmp/noctalia-W
# TOML file -> sorted "dotted.path = <json value>" lines
# NOT paths(scalars): jq truthiness drops every `false`/`null` leaf, hiding real overrides
# (`dock.reserve_space = false` and friends vanish from both diffs).
leaves() { $YQ -ftoml -ojson . "$1" 2>/dev/null | ( ulimit -v 2000000; jq -rS 'paths(type != "array" and type != "object") as $p | ($p|join(".")) + " = " + (getpath($p)|tojson)' | sort ); }
```

`$W` is tmpfs and a reboot clears it mid-run: recover it from `/tmp/noctalia-W`, and remember the
module edit is the only durable artifact — regenerate `$W/new.toml` from the module after a restart.
Other traps: NixOS has no `/bin/bash` (script files need `#!/run/current-system/sw/bin/bash`), and jq
treats a positional filter as a filename (`jq -c '.x' f.json | jq -r -f prog.jq`, never `jq -r -f
prog.jq '.x' f.json` — it reports a missing file and the pipeline yields nothing at all).

Prerequisites: the shell must be running for `noctalia config export` — use
`systemctl --user is-active noctalia`; `pgrep -x noctalia` does NOT match it. `$STATE` may be absent,
in which case there is nothing to sync — say so and stop. Confirm the Settings window is closed:
`hyprctl clients -j | jq -r '.[] | "\(.class) \(.title)"' | grep -i -E 'noctalia|settings'` is empty.

## 1. Render the current declarative config from the working tree

```bash
nix build --impure --quiet --print-out-paths --expr "
  let pkgs = import <nixpkgs> { config = {}; overlays = []; };
      m = import $MODULE { inherit pkgs; };
  in (pkgs.formats.toml {}).generate \"config.toml\" m.programs.noctalia.settings" -o "$W/declared.toml"
leaves "$STATE" > "$W/state.leaves"; leaves "$W/declared.toml" > "$W/declared.leaves"
comm -23 "$W/state.leaves" "$W/declared.leaves"
```

Each output line is one override the Nix config does not yet produce (identical leaves disappear).
Group them by top-level section, apply the argument filter and the rules above, and show the list.
Empty list → nothing to add to Nix. If `$STATE` still holds sections whose leaves all match
`$W/declared.toml`, jump to step 4 (skip the switch only when `diff "$HOME/.config/noctalia/config.toml"
"$W/declared.toml"` is already clean) and continue with the cleanup. Otherwise stop here.

## 2. Write the missing values into Nix

Edit `settings` in `$MODULE`. TOML → Nix: `[table.sub]` → nested attrsets, arrays → lists,
`196.0` → `196.0` (keep floats floats), strings quoted, booleans `true`/`false`. Merge into an
existing section rather than adding a second one (`theme.mode` already exists — extend it). Do not
reorder or reformat unrelated entries; keep the file's existing comment style and add a short comment
only where the value is non-obvious — and verify it before writing one: `noctalia` has no schema dump,
so semantics come from upstream `example.toml`
(<https://raw.githubusercontent.com/noctalia-dev/noctalia/main/example.toml>, has inline comments for
most keys) and docs.noctalia.dev. Guessing a comment is worse than none. The docs lag the shell, so
they are not a filter either: `widget.media.show_progress` appears in no `example.toml` or docs table
yet validates clean on 5.2.1 — drop a key only on a real `WARN unknown setting`.

The editor sections are long but mechanical: a widget is keyed by its id, so an id with `@` needs
quoting (`"lockscreen-login-box@DP-1" = { … };`), its `settings` is a nested attrset, and `widget_order`
must keep its exact order (it is the z-order) while everything else may be alphabetical.

Then lint the module: `nix run nixpkgs#nixfmt -- --check $MODULE` (this flake exports no formatter, so
`nix fmt` errors out) plus `statix` and `deadnix`, which must stay at 0 warnings — a run of dotted keys
in one attrset (`settings.stat = …; settings.stat2 = …;`) trips "Avoid repeated keys in attribute sets",
so write `settings = { stat = …; stat2 = …; };`.

## 3. Validate before switching

```bash
nix build --impure --quiet --print-out-paths --expr "
  let pkgs = import <nixpkgs> { config = {}; overlays = []; };
      m = import $MODULE { inherit pkgs; };
  in (pkgs.formats.toml {}).generate \"config.toml\" m.programs.noctalia.settings" -o "$W/new.toml"
noctalia config validate "$W/new.toml"
leaves "$W/new.toml" > "$W/new.leaves"
comm -23 "$W/state.leaves" "$W/new.leaves"   # empty, or only never / ASK / float32-artifact keys
```

`noctalia config validate` must print `✓ Config is valid`. On `ERROR` fix the Nix and repeat. On
`WARN ... unknown setting` the GUI wrote a key the current schema ignores: drop it, report it.
If the user touched the GUI while you worked, re-run step 1: the shell rewrites/prunes `$STATE` at
any moment, so it is never a snapshot.

## 4. Apply

Ask the user, then `sudo nh os switch "$REPO"`. Most users would rather run the sudo step themselves:
if so, stop after step 3 and hand over that command, the check below and the step 5 commands, then
finish 4–6 once they say it landed. Confirm the switch landed before touching state:

```bash
diff "$(readlink -f ~/.config/noctalia/config.toml)" "$W/new.toml" && echo DECLARATIVE-LAYER-OK
```

## 5. Delete the migrated overrides

```bash
leaves "$STATE" > "$W/state2.leaves"; diff "$W/state.leaves" "$W/state2.leaves"  # re-check for GUI writes
cp "$STATE" "$STATE.bak.$(date +%F-%H%M%S)"
$YQ -ftoml -otoml -i 'del(.theme)' "$STATE"        # one del() entry per fully-migrated top-level section
```

Rules: `-ftoml -otoml` is mandatory (plain `-i` writes YAML into the `.toml` file). Delete only
sections whose leaves are now all declared; leave partially-migrated sections in place and report
them. Always keep `config_version`. If nothing but `config_version` remains, keep the file — deleting
it is allowed but forces a re-migration stamp. A backup must exist before any deletion.

## 6. Prove the result

```bash
noctalia config export > "$W/effective.toml"
leaves "$W/effective.toml" > "$W/eff.leaves"
comm -23 "$W/eff.leaves" "$W/new.leaves"    # only never/ASK leftovers allowed
```

The merged effective config must equal the declarative one apart from whitelisted leftovers.
Config hot-reloads via inotify; if the running shell still shows old values, `systemctl --user restart noctalia`.

## 7. Report

- migrated keys as `dotted.path = value` and where they landed in `$MODULE`
- leftovers kept in the state file and why (ASK list / partial section / unknown key / float32)
- secrets refused for the repo
- backup path, and the exact command to roll back the state file
- whether a rebuild was applied or still needs `sudo nh os switch $REPO`
