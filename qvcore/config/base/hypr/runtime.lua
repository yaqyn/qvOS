-- Shared qvOS Hyprland Lua helpers.

qv = qv or {}

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function direction(value)
  local directions = {
    l = "left",
    r = "right",
    u = "up",
    d = "down",
    left = "left",
    right = "right",
    up = "up",
    down = "down",
  }

  return directions[trim(value)]
end

local function vector(value, label)
  local x, y = value:match("^%s*(%S+)%s+(%S+)%s*$")
  x = tonumber(x)
  y = tonumber(y)
  if not x or not y or x % 1 ~= 0 or y % 1 ~= 0 then
    error(label .. ": expected two integer coordinates")
  end

  return x, y
end

local function rule_value(value)
  value = trim(value)
  if value == "" or value == "on" or value == "true" then
    return true
  elseif value == "off" or value == "false" then
    return false
  elseif tonumber(value) then
    return tonumber(value)
  end

  return value
end

local function rule_spec(effect, match)
  local key, value = effect:match("^(%S+)%s*(.*)$")
  if not key then
    error("qvOS Hyprland rule: empty effect")
  end

  local spec = { match = match }
  spec[key] = rule_value(value)
  return spec
end

function qv.window_rule(effect, match)
  return hl.window_rule(rule_spec(effect, match))
end

function qv.layer_rule(effect, match)
  return hl.layer_rule(rule_spec(effect, match))
end

function qv.device(name, enabled)
  hl.device({ name = name, enabled = enabled })
end

function qv.require_optional_wildcard(path)
  if type(path) ~= "string" or not path:match("/%*%.lua$") then
    error("qvOS optional Hyprland source must be a Lua wildcard")
  end

  local loaded, load_error = pcall(require, path)
  if loaded then
    return
  end

  load_error = tostring(load_error)
  local absent_error = "module '" .. path .. "' not found: wildcard found no match"
  if load_error == absent_error then
    return
  end
  error(load_error, 0)
end

local function dispatcher(name, argument)
  argument = argument or ""

  if name == "exec" then
    return hl.dsp.exec_cmd(argument)
  elseif name == "fullscreenstate" then
    local internal, client = vector(argument, name)
    return hl.dsp.window.fullscreen_state({
      internal = internal,
      client = client,
      action = "set",
    })
  elseif name == "togglefloating" then
    return hl.dsp.window.float({ action = "toggle" })
  elseif name == "movefocus" then
    return hl.dsp.focus({ direction = assert(direction(argument), "invalid focus direction") })
  elseif name == "resizeactive" then
    local x, y = vector(argument, name)
    return hl.dsp.window.resize({ x = x, y = y, relative = true })
  elseif name == "swapwindow" then
    return hl.dsp.window.swap({ direction = assert(direction(argument), "invalid swap direction") })
  elseif name == "movecurrentworkspacetomonitor" then
    return hl.dsp.workspace.move({ monitor = argument })
  elseif name == "workspace" then
    return hl.dsp.focus({ workspace = argument })
  elseif name == "movetoworkspace" then
    return hl.dsp.window.move({ workspace = argument, follow = true })
  elseif name == "movetoworkspacesilent" then
    return hl.dsp.window.move({ workspace = argument, follow = false })
  elseif name == "togglespecialworkspace" then
    return hl.dsp.workspace.toggle_special(argument)
  elseif name == "killactive" then
    return hl.dsp.window.close()
  elseif name == "layoutmsg" then
    return hl.dsp.layout(argument)
  elseif name == "pseudo" then
    return hl.dsp.window.pseudo({ action = "toggle" })
  elseif name == "fullscreen" then
    local mode = trim(argument) == "1" and "maximized" or "fullscreen"
    return hl.dsp.window.fullscreen({ mode = mode, action = "toggle" })
  elseif name == "focusmonitor" then
    return hl.dsp.focus({ monitor = argument })
  elseif name == "movewindow" then
    return hl.dsp.window.drag()
  elseif name == "resizewindow" then
    return hl.dsp.window.resize()
  elseif name == "togglegroup" then
    return hl.dsp.group.toggle()
  elseif name == "moveoutofgroup" then
    return hl.dsp.window.move({ out_of_group = true })
  elseif name == "moveintogroup" then
    return hl.dsp.window.move({ into_group = assert(direction(argument), "invalid group direction") })
  elseif name == "changegroupactive" then
    argument = trim(argument)
    if argument == "f" then
      return hl.dsp.group.next()
    elseif argument == "b" then
      return hl.dsp.group.prev()
    end
    return hl.dsp.group.active({ index = assert(tonumber(argument), "invalid group index") })
  elseif name == "sendshortcut" then
    local mods, key, window = argument:match("^%s*([^,]+),%s*([^,]+),%s*(.-)%s*$")
    if not mods then
      error("sendshortcut: expected modifiers, key, and window")
    end
    return hl.dsp.send_shortcut({
      mods = trim(mods),
      key = trim(key),
      window = trim(window),
    })
  end

  error("unsupported qvOS Hyprland dispatcher: " .. name)
end

function qv.bind(spec)
  hl.bind(spec.keys, dispatcher(spec.dispatcher, spec.argument), {
    description = spec.description,
    locked = spec.locked,
    release = spec.release,
    repeating = spec.repeating,
  })
end

local autostart_commands = {}

function qv.autostart(command)
  if type(command) ~= "string" or command == "" then
    error("qvOS autostart commands must be non-empty strings")
  end
  table.insert(autostart_commands, command)
end

function qv.start_autostart()
  hl.on("hyprland.start", function()
    for _, command in ipairs(autostart_commands) do
      hl.exec_cmd(command)
    end
  end)
end
