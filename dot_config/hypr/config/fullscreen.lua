local fullscreen = {}
local soft_sessions = {}
local setting_fullscreen_state = false

local NONE = 0
local MAXIMIZED = 1
local FULLSCREEN = 2

local function set_fullscreen_state(window, internal_mode, client_mode)
  setting_fullscreen_state = true
  for _ = 1, 2 do
    hl.dispatch(hl.dsp.window.fullscreen_state({
      internal = internal_mode,
      client = client_mode,
      action = "set",
      window = window,
    }))
    local current_window = hl.get_window("address:" .. window.address)
    if not current_window or
      (current_window.fullscreen == internal_mode and current_window.fullscreen_client == client_mode) then break end
  end
  setting_fullscreen_state = false
end

hl.on("window.update_rules", function(window)
  if setting_fullscreen_state or not soft_sessions[window.address] or window.fullscreen_client == FULLSCREEN then return end
  soft_sessions[window.address] = nil
  if window.fullscreen ~= NONE or window.fullscreen_client ~= NONE then set_fullscreen_state(window, NONE, NONE) end
end)

hl.on("window.close", function(window)
  soft_sessions[window.address] = nil
end)

function fullscreen.toggle_max()
  local window = hl.get_active_window()
  if not window then return end
  if window.fullscreen == FULLSCREEN then
    soft_sessions[window.address] = nil
    set_fullscreen_state(window, NONE, NONE)
  else
    set_fullscreen_state(window, FULLSCREEN, FULLSCREEN)
  end
end

function fullscreen.toggle_soft()
  local window = hl.get_active_window()
  if not window then return end
  if window.fullscreen == MAXIMIZED and soft_sessions[window.address] then
    soft_sessions[window.address] = nil
    set_fullscreen_state(window, NONE, NONE)
  else
    soft_sessions[window.address] = true
    set_fullscreen_state(window, MAXIMIZED, FULLSCREEN)
  end
end

return fullscreen
