-- Ignore maximize requests from apps; tiling layouts almost always want this.
hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

-- XWayland dragging fix from the upstream example config.
hl.window_rule({
  name = "fix-xwayland-drags",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- pinentry windows (git commit -S) must not lose focus. Confirm the class with
-- `hyprctl clients -j | jq -r '.[].class' | rg -i pinentry` and tighten if needed.
hl.window_rule({ name = "keep-pinentry", match = { class = "(pinentry)(.*)" }, stay_focused = true })

-- Noctalia's Settings window (upstream-recommended).
hl.window_rule({ match = { class = "dev.noctalia.Noctalia" }, float = true, size = { 1080, 920 } })

-- "No gaps when only": dwindle.no_gaps_when_only does not exist in 0.56.
hl.workspace_rule({ workspace = "w[tv1]", gaps_in = 0, gaps_out = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_in = 0, gaps_out = 0 })

-- Keep Hyprland's built-in layer animations off Noctalia's own surfaces (upstream's exact pattern;
-- bar surfaces are named per bar instance, e.g. noctalia-bar-default).
hl.layer_rule({
  name = "noctalia",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
  no_anim = true,
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})
