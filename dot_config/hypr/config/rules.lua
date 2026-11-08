local SpecialApps = {
  ["special:home-assistant"] = HomeAssistant,
  ["special:whatsapp"] = Whatsapp,
}

hl.on("workspace.created", function(ws)
  local cmd = SpecialApps[ws.name]
  if cmd and ws.is_empty then hl.exec_cmd(cmd) end
end)

hl.window_rule({
  match = { class = "^(chrome-home\\.cuasar\\.cc__-Default)$" },
  workspace = "special:home-assistant silent",
  no_initial_focus = true,
})

hl.window_rule({
  match = { class = "^(brave-web\\.whatsapp\\.com__-Default)$" },
  workspace = "special:whatsapp silent",
  no_initial_focus = true,
})

hl.window_rule({
  match = { class = "^(puppeteer-browser)$" },
  workspace = "1 silent",
  float = false,
  size = { 1920, 1080 },
  center = true,
})

hl.window_rule({
  name = "Bitwarden",
  match = { class = "^brave-nngceckbapebfimnlniiiahkandclblb-.*$" },
  float = true,
  size = { 480, 630 },
  center = true,
})

hl.window_rule({
  match = { class = "^(org.gnome.Calculator)$" },
  float = true,
  size = { 300, 616 },
  center = true,
})

hl.window_rule({
  match = { class = "^(qimgv)$" },
  float = true,
})

hl.window_rule({
  match = { initial_class = "^(ephemeral-kitty)$" },
  float = true,
})

hl.window_rule({
  match = { class = "^(steam)$" },
  float = false,
})

hl.window_rule({
  match = { class = "^(vicinae)$" },
  border_size = 0,
})

hl.window_rule({
  -- Ignore maximize requests from all apps
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

hl.window_rule({
  -- Fix some dragging issues with XWayland
  name = "fix-xwayland-drags",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_focus = true,
})
