hl.workspace_rule({
  workspace = "special:home-assistant",
  on_created_empty = "chromium --new-window --app=https://home.cuasar.cc",
})

hl.window_rule({
  workspace = "special:home-assistant silent",
  no_initial_focus = true,
  match = { class = "^(chrome-home\\.cuasar\\.cc__-Default)$" },
})

hl.window_rule({
  name   = "Bitwarden",
  match  = { class = "^(brave-nngceckbapebfimnlniiiahkandclblb-Default)$" },
  float  = true,
  size   = { 380, 600 },
  center = true,
})

hl.window_rule({
  match  = { class = "^(org.gnome.Calculator)$" },
  float  = true,
  size   = { 300, 616 },
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
  workspace = "1 silent",
  match     = { class = "^(puppeteer-browser)$" },
  float     = false,
  size      = { 1920, 1080 },
  center    = true,
})

hl.window_rule({
  match = { class = "^(gjs)$" },
  float = true,
  persistent_size = true,
})

hl.window_rule({
  match = { class = "^(GTK Application)$" },
  float = true,
  persistent_size = true,
})

hl.window_rule({
  match = { class = "^(vicinae)$" },
  border_size = 0,
})

hl.layer_rule({
  match = { namespace = "vicinae" },
  ignore_alpha = 0,
  blur = true,
})

hl.layer_rule({
  match = { namespace = "waybar" },
  ignore_alpha = 0,
  blur = true,
})

hl.layer_rule({
  match = { namespace = "swaync-control-center" },
  animation = "slide top",
})

hl.layer_rule({
  match = { namespace = "swaync-notification-window" },
  animation = "slide top",
})

hl.layer_rule({
  match = { namespace = "quick-settings" },
  animation = "slide right",
})

hl.layer_rule({
  match = { namespace = "osd" },
  animation = "slide bottom",
})

hl.layer_rule({
  match = { namespace = "osd" },
  ignore_alpha = 0,
  above_lock = 1,
  xray = true,
  blur = false,
})

hl.window_rule({
  -- Ignore maximize requests from all apps
  name           = "suppress-maximize-events",
  match          = { class = ".*" },

  suppress_event = "maximize",
})

hl.window_rule({
  -- Fix some dragging issues with XWayland
  name     = "fix-xwayland-drags",
  match    = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },

  no_focus = true,
})
