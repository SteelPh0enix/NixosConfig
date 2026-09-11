local mod = "SUPER"
local terminal = "wezterm"
local fileManager = "thunar"
local ipc = "noctalia msg "

-- applications and shell surfaces
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal), { description = "Terminal (Plasma habit)" })
hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"), { description = "Launcher" })
hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "File manager" })
hl.bind(mod .. " + S", hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"), { description = "Control center" })
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd(ipc .. "panel-toggle clipboard"), { description = "Clipboard history" })
hl.bind(mod .. " + TAB", hl.dsp.exec_cmd(ipc .. "window-switcher"), { description = "Window switcher" })
hl.bind(mod .. " + comma", hl.dsp.exec_cmd(ipc .. "settings-toggle"), { description = "Noctalia settings" })
-- Noctalia's own lock screen; hyprlock is not installed at all
hl.bind(mod .. " + L", hl.dsp.exec_cmd(ipc .. "session lock"), { description = "Lock screen" })
-- never hl.dsp.exit() under uwsm; Noctalia's Log out button is overridden for the same reason
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("uwsm stop"), { description = "End session" })

-- window
hl.bind(mod .. " + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mod .. " + P", hl.dsp.window.pseudo(), { description = "Pseudo-tile" })
hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split" })

-- focus: arrow keys, like the upstream example config. Deliberately not h/j/k/l: key lookup is
-- case-insensitive, so `SUPER + J` (togglesplit, above) and a lowercase `j` bind would be one chord.
hl.bind(mod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))

-- workspaces 1-10 (SUPER+0 = 10), SHIFT = move window
for i = 1, 10 do
  local key = i % 10
  hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }), { description = "Workspace " .. i })
  hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move to workspace " .. i })
end
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- No scratchpad: `SUPER + S` belongs to the control centre. For the upstream special-workspace
-- pattern (hl.dsp.workspace.toggle_special / window.move{workspace = "special:magic"}), pick a
-- free chord -- and remember one key may only carry one bind.

-- audio / media / brightness (PipeWire and DDC/CI handled inside the shell)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(ipc .. "volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(ipc .. "volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(ipc .. "volume-mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(ipc .. "mic-mute"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(ipc .. "media toggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(ipc .. "media next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(ipc .. "media previous"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(ipc .. "brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"), { locked = true, repeating = true })

-- screenshots (Noctalia captures via wlr-screencopy; output policy in the Noctalia config). There
-- is no annotate IPC verb; screenshot-fullscreen takes pick | monitor | all.
hl.bind("Print", hl.dsp.exec_cmd(ipc .. "screenshot-region"), { description = "Screenshot: region" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(ipc .. "screenshot-fullscreen"), { description = "Screenshot: focused monitor" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(ipc .. "screenshot-fullscreen pick"), { description = "Screenshot: pick monitor" })

-- drag / resize (these two dispatchers need the mouse flag)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
