Name = "qvosMenu"
NamePretty = "qvOS"
Cache = false
FixedOrder = true
HideFromProviderlist = true
Actions = {
  toggle = "lua:ToggleMode",
}

local function shell_escape(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function route(name)
  return "omarchy-menu " .. shell_escape(name)
end

local function mode_path()
  local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
  return runtime_dir and runtime_dir .. "/qvos-menu-mode" or nil
end

local function view_path()
  local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
  return runtime_dir and runtime_dir .. "/qvos-menu-view" or nil
end

local function read_mode()
  local path = mode_path()
  local mode_file = path and io.open(path, "r")

  if not mode_file then
    return "menu"
  end

  local mode = mode_file:read("*l")
  mode_file:close()

  return mode == "apps" and "apps" or "menu"
end

local function read_view()
  local path = view_path()
  local view_file = path and io.open(path, "r")

  if not view_file then
    return "home"
  end

  local view = view_file:read("*l")
  view_file:close()

  if view == "software" or view:match("^software:[%w-]+$") then
    return view
  end
  return "home"
end

local function write_mode(mode)
  local path = mode_path()
  local mode_file = path and io.open(path, "w")

  if not mode_file then
    return
  end

  mode_file:write(mode, "\n")
  mode_file:close()
end

function ToggleMode()
  write_mode(read_mode() == "apps" and "menu" or "apps")
end

function ShowApps()
  write_mode("apps")
end

function ShowMenu()
  write_mode("menu")
end

local function terminal(command)
  return "xdg-terminal-exec --app-id=org.omarchy.terminal " .. command
end

local function edit(relative_path)
  return "notify-send -u low "
    .. shell_escape("Editing config file")
    .. " "
    .. shell_escape(relative_path)
    .. "; omarchy-launch-editor \"$HOME/"
    .. relative_path
    .. "\""
end

local function qvos_owner(relative_path, ...)
  local home = os.getenv("HOME")
  local source = os.getenv("OMARCHY_PATH")
    or (home and home .. "/.local/share/omarchy")

  if not source then
    return nil
  end

  local command = shell_escape(source .. "/" .. relative_path)
  for _, argument in ipairs({ ... }) do
    command = command .. " " .. shell_escape(argument)
  end
  return command
end

local function qvos_tui_owner(relative_path, ...)
  local home = os.getenv("HOME")

  if not home then
    return nil
  end

  local command = shell_escape(home .. "/.local/share/qvos/tui/" .. relative_path)
  for _, argument in ipairs({ ... }) do
    command = command .. " " .. shell_escape(argument)
  end
  return command
end

local function task_action(slug)
  return qvos_tui_owner("task/launch", slug)
    or "omarchy-launch-qvos-task " .. shell_escape(slug)
end

local function install_font(slug)
  return qvos_tui_owner("action/font-launch", slug)
    or route("install-font")
end

local function add(entries, icon, text, breadcrumb, keywords, action)
  table.insert(entries, {
    Text = icon .. "  " .. text,
    Subtext = breadcrumb,
    Keywords = keywords,
    Actions = { activate = action },
  })
end

local function home_entries()
  return {
    {
      Text = "󰀻  All Apps",
      Keywords = { "apps", "applications", "launch" },
      Actions = { show_apps = "lua:ShowApps" },
    },
    {
      Text = "󱅾  Update qvOS",
      Keywords = { "update", "upgrade", "sync" },
      Actions = { activate = "omarchy-launch-qvos-update" },
    },
    {
      Text = "  Settings",
      Keywords = { "settings", "setup", "configure", "software", "appearance" },
      Actions = { activate = route("settings") },
    },
    {
      Text = "󰍜  More",
      Keywords = { "more", "learn", "capture", "share", "about", "power" },
      Actions = { activate = route("more") },
    },
  }
end

local function query_apps(query, activation_query)
  if type(jsonDecode) ~= "function" then
    return {}
  end

  local request = "desktopapplications;" .. query .. ";256;false"
  local handle = io.popen(
    "elephant query " .. shell_escape(request) .. " --json 2>/dev/null"
  )

  if not handle then
    return {}
  end

  local entries = {}

  for line in handle:lines() do
    local decoded, response = pcall(jsonDecode, line)
    local app = decoded and response and response.item

    if app and app.identifier and app.text then
      local activation = table.concat({
        "desktopapplications",
        app.identifier:gsub(";", " "),
        "start",
        activation_query,
        "",
      }, ";")

      table.insert(entries, {
        Text = app.text,
        Subtext = app.subtext or "Installed App",
        Icon = app.icon or "",
        Keywords = { activation_query, app.text, app.subtext or "" },
        Actions = {
          activate = "elephant activate " .. shell_escape(activation),
        },
      })
    end
  end

  handle:close()

  return entries
end

local function app_entries(query)
  local safe_query = query:gsub(";", " ")
  local candidate = safe_query
  local entries = query_apps(candidate, safe_query)

  while #entries == 0 and #candidate > 3 do
    candidate = candidate:sub(1, -2)
    entries = query_apps(candidate, safe_query)
  end

  if #entries > 0 then
    return entries
  end

  local description = safe_query == ""
      and "No installed apps were found"
    or "No installed app matches “" .. safe_query .. "”"

  return {
    {
      Text = description,
      Subtext = "Press Tab or Return to go back to Menu",
      Keywords = { safe_query },
      Actions = { show_menu = "lua:ShowMenu" },
    },
  }
end

local function split(value, separator)
  local parts = {}

  for part in (value .. separator):gmatch("(.-)" .. separator) do
    table.insert(parts, part)
  end

  return parts
end

local function normalize_intent(value)
  return value:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function entry_name(entry)
  return entry.Text:match("^.-  (.*)$") or entry.Text
end

local search_intents_cache

local function load_search_intents()
  if search_intents_cache then
    return search_intents_cache
  end

  search_intents_cache = {
    aliases_by_target = {},
    target_by_intent = {},
  }

  local home = os.getenv("HOME")
  local intents = home
    and io.open(home .. "/.local/share/qvos/menu/search-intents.psv", "r")

  if not intents then
    return search_intents_cache
  end

  for line in intents:lines() do
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local intent, target = line:match("^([^|]+)|([^|]+)$")

      if intent and target then
        local normalized_intent = normalize_intent(intent)
        local aliases = search_intents_cache.aliases_by_target
        aliases[target] = aliases[target] or {}
        table.insert(aliases[target], normalized_intent)
        search_intents_cache.target_by_intent[normalized_intent] = target
      end
    end
  end

  intents:close()
  return search_intents_cache
end

local function apply_search_intents(entries, query)
  local intents = load_search_intents()
  local exact_target = intents.target_by_intent[normalize_intent(query)]
  local exact_entries = {}

  for _, entry in ipairs(entries) do
    local name = entry_name(entry)
    local aliases = intents.aliases_by_target[name]

    if aliases then
      for _, alias in ipairs(aliases) do
        table.insert(entry.Keywords, alias)
      end
    end

    if exact_target == name then
      table.insert(exact_entries, entry)
    end
  end

  if exact_target and #exact_entries == 1 then
    return exact_entries
  end

  return entries
end

local function software_action_states()
  local home = os.getenv("HOME")
  local source = os.getenv("OMARCHY_PATH")
    or (home and home .. "/.local/share/omarchy")
  local owner = source and source .. "/qvcore/menu/software-state"
  local handle = owner and io.popen(shell_escape(owner) .. " --all 2>/dev/null")
  local states = {}

  if not handle then
    return states
  end
  for line in handle:lines() do
    local slug, state = line:match("^([%w-]+)\t([%a]+)$")
    if slug and (state == "install" or state == "uninstall") then
      states[slug] = state
    end
  end
  handle:close()
  return states
end

local function software_action(slug)
  local home = os.getenv("HOME")
  local launch = home and home .. "/.local/share/qvos/tui/action/launch"

  return launch and shell_escape(launch) .. " " .. shell_escape(slug)
    or route("concept:" .. slug)
end

local function software_installer(slug)
  local home = os.getenv("HOME")
  local action = "action/launch"
  local arguments = { "--installer", slug }

  if slug == "alacritty"
    or slug == "foot"
    or slug == "ghostty"
    or slug == "kitty"
  then
    action = "action/terminal-launch"
    arguments = { slug }
  end

  local launch = home and home .. "/.local/share/qvos/tui/" .. action

  return launch and shell_escape(launch)
      .. " "
      .. shell_escape(arguments[1])
      .. (arguments[2] and " " .. shell_escape(arguments[2]) or "")
    or route("install")
end

local function add_software_installers(entries, breadcrumb)
  local home = os.getenv("HOME")
  local path = home
    and home .. "/.local/share/qvos/menu/software-installers.psv"
  local catalog = path and io.open(path, "r")

  if not catalog then
    return
  end

  for line in catalog:lines() do
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local fields = split(line, "|")
      if #fields == 11 and fields[4] == breadcrumb then
        add(
          entries,
          fields[2],
          fields[3],
          fields[4],
          split(fields[5], ","),
          software_installer(fields[1])
        )
      end
    end
  end

  catalog:close()
end

local function software_group_matches(breadcrumb, view)
  if view == "software" then
    return breadcrumb:match("^Settings · Software ·") ~= nil
      or breadcrumb == "Settings · Software"
  end

  local group = view:match("^software:(.+)$")
  local group_breadcrumbs = {
    development = "Settings · Software · Development",
    javascript = "Settings · Software · Development · JavaScript",
    browser = "Settings · Software · Browser",
    gaming = "Settings · Software · Gaming",
    services = "Settings · Software · Services",
  }
  local expected = group and group_breadcrumbs[group]
  return expected and breadcrumb:sub(1, #expected) == expected or false
end

local software_selectors = {
  package = "Manage",
  ["web-app"] = "Manage",
  tui = "Manage",
  services = "Browse",
  editor = "Browse",
  terminal = "Browse",
  ai = "Browse",
}

local function add_concepts(entries, software_view)
  local home = os.getenv("HOME")
  local catalog = home and io.open(home .. "/.local/share/qvos/menu/concepts.psv", "r")
  local action_states = software_action_states()

  if not catalog then
    return
  end

  for line in catalog:lines() do
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local fields = split(line, "|")
      local state = action_states[fields[1]]
      local visible = not software_view
        or (
          software_view == "software"
          and (state or software_selectors[fields[1]])
        )
        or (
          state
          and software_group_matches(fields[4], software_view)
        )

      if visible then
        local subtext = fields[4]
        local activation = route("concept:" .. fields[1])

        if state then
          subtext = ""
          activation = software_action(fields[1])
        elseif software_view == "software"
          and software_selectors[fields[1]]
        then
          subtext = ""
          if fields[6] == "Browse"
            and fields[7] and fields[7]:match("^menu:")
          then
            activation = route(fields[7]:sub(6))
          end
        end

        add(
          entries,
          fields[2],
          fields[3],
          subtext,
          split(fields[5], ","),
          activation
        )
      end
    end
  end

  catalog:close()
end

function GetEntries(query)
  query = query or ""

  if read_mode() == "apps" then
    return app_entries(query)
  end

  local view = read_view()
  if view == "software" or view:match("^software:") then
    local entries = {}
    add_concepts(entries, view)
    if view == "software:services" then
      add_software_installers(entries, "Settings · Software · Services")
    elseif view == "software:development" then
      add_software_installers(entries, "Settings · Software · Development")
    end
    return apply_search_intents(entries, query)
  end

  if query == "" then
    return home_entries()
  end

  local entries = {}

  -- Home and first-level destinations.
  add(entries, "󰀻", "All Apps", "Home", { "apps", "applications", "launch" }, route("apps"))
  add(entries, "󱅾", "Update qvOS", "Home", { "update", "upgrade", "sync" }, "omarchy-launch-qvos-update")
  add(entries, "", "Settings", "Home", { "setup", "configure", "software", "appearance" }, route("settings"))
  add(entries, "󰍜", "More", "Home", { "learn", "capture", "share", "about", "power" }, route("more"))
  add(entries, "󰧑", "Learn", "More", { "docs", "help", "manual" }, route("learn"))
  add(entries, "", "About", "More", { "omarchy", "version", "credits" }, "omarchy-launch-about")

  -- Concepts appear once; opening one reveals its available actions.
  add_concepts(entries)

  -- Learn.
  add(entries, "", "qvOS Source", "More · Learn", { "docs", "help", "github" }, "omarchy-launch-webapp https://github.com/Yaqyn-qvOS/qvOS")
  add(entries, "", "Hyprland Wiki", "More · Learn", { "docs", "help" }, "omarchy-launch-webapp https://wiki.hypr.land/")
  add(entries, "󰣇", "Arch Wiki", "More · Learn", { "docs", "help" }, "omarchy-launch-webapp https://wiki.archlinux.org/title/Main_page")
  add(entries, "", "Neovim Keymaps", "More · Learn", { "lazyvim", "vim", "docs" }, "omarchy-launch-webapp https://www.lazyvim.org/keymaps")
  add(entries, "󱆃", "Bash Reference", "More · Learn", { "shell", "docs" }, "omarchy-launch-webapp https://devhints.io/bash")

  -- More.
  add(entries, "󰔛", "Reminder", "More", { "timer", "notify" }, route("reminder"))
  add(entries, "󰔛", "Set Reminder", "More · Reminder", { "timer", "notify" }, route("reminder-set"))
  add(entries, "󰔛", "Show Reminders", "More · Reminder", { "timer", "list" }, "omarchy-reminder show")
  add(entries, "󰔛", "Clear Reminders", "More · Reminder", { "timer", "delete" }, "omarchy-reminder clear")
  add(entries, "", "Capture", "More", { "screenshot", "record", "color" }, route("capture"))
  add(entries, "", "Screenshot", "More · Capture", { "screen", "image" }, "omarchy-capture-screenshot")
  add(entries, "", "Screenrecord", "More · Capture", { "video", "record" }, route("screenrecord"))
  add(entries, "", "Screenrecord Without Audio", "More · Capture · Screenrecord", { "video", "silent" }, "omarchy-capture-screenrecording")
  add(entries, "", "Screenrecord Desktop Audio", "More · Capture · Screenrecord", { "video", "sound" }, "omarchy-capture-screenrecording --with-desktop-audio")
  add(entries, "", "Screenrecord Desktop + Microphone", "More · Capture · Screenrecord", { "video", "sound", "mic" }, "omarchy-capture-screenrecording --with-desktop-audio --with-microphone-audio")
  add(entries, "󰴑", "Text Extraction", "More · Capture", { "ocr", "copy" }, "omarchy-capture-text-extraction")
  add(entries, "󰃉", "Color Picker", "More · Capture", { "hyprpicker", "copy" }, "pkill hyprpicker || hyprpicker -a")
  add(entries, "󰧸", "Transcode", "More", { "convert", "media" }, "omarchy-transcode")
  add(entries, "", "Share Clipboard", "More · Share", { "localsend", "send" }, "omarchy-qvos-share clipboard")
  add(entries, "", "Share File", "More · Share", { "localsend", "send" }, terminal("bash -c " .. shell_escape("omarchy-qvos-share file")))
  add(entries, "", "Share Folder", "More · Share", { "localsend", "send" }, terminal("bash -c " .. shell_escape("omarchy-qvos-share folder")))
  add(entries, "󰔎", "Toggles", "More", { "switch", "desktop" }, route("toggle"))
  add(entries, "󰔎", "Nightlight", "More · Toggles", { "toggle", "warm" }, "omarchy-toggle-nightlight")
  add(entries, "󱫖", "Idle Lock", "More · Toggles", { "toggle", "sleep" }, "omarchy-toggle-idle")
  add(entries, "󰂛", "Notifications", "More · Toggles", { "toggle", "silence" }, "omarchy-toggle-notification-silencing")
  add(entries, "󰍜", "Top Bar", "More · Toggles", { "toggle", "waybar" }, "omarchy-toggle-waybar")
  add(entries, "󱂬", "Workspace Layout", "More · Toggles", { "toggle", "hyprland" }, "omarchy-hyprland-workspace-layout-toggle")
  add(entries, "", "Window Gaps", "More · Toggles", { "toggle", "hyprland" }, "omarchy-hyprland-window-gaps-toggle")
  add(entries, "", "1-Window Ratio", "More · Toggles", { "toggle", "square" }, "omarchy-hyprland-window-single-square-aspect-toggle")
  add(entries, "󰍹", "Monitor Scaling", "More · Toggles", { "display", "scale" }, "omarchy-hyprland-monitor-scaling-cycle")
  add(entries, "", "Direct Boot", "More · Toggles", { "limine", "boot" }, task_action("direct-boot"))
  add(entries, "󰛧", "Laptop Display", "Settings · Devices", { "monitor", "toggle" }, "omarchy-hyprland-monitor-internal toggle")
  add(entries, "󰍹", "Mirror Display", "Settings · Devices", { "monitor", "toggle" }, "omarchy-hyprland-monitor-internal-mirror toggle")
  add(entries, "", "Hybrid GPU", "Settings · Devices", { "graphics", "toggle" }, task_action("hybrid-gpu"))
  add(entries, "󰟸", "Touchpad", "Settings · Devices", { "toggle", "input" }, "omarchy-toggle-touchpad")
  add(entries, "󰆽", "Touchscreen", "Settings · Devices", { "toggle", "input" }, "omarchy-toggle-touchscreen")
  add(entries, "󰌌", "Touchpad Haptics", "Settings · Devices", { "dell", "vibration" }, route("hardware"))

  -- Canonical settings objects live in the concept catalog. Detailed config
  -- files remain searchable without becoming another browse tree.
  add(entries, "", "Default Browser", "Settings · System · Defaults", { "launch", "web" }, route("setup-defaults"))
  add(entries, "", "Default Terminal", "Settings · System · Defaults", { "launch", "shell" }, route("setup-defaults"))
  add(entries, "", "Default Editor", "Settings · System · Defaults", { "launch", "code" }, route("setup-defaults"))
  add(entries, "", "Hyprland Config", "Settings · System · Config", { "reset", "default" }, edit(".config/hypr/hyprland.conf"))
  add(entries, "", "Hypridle Config", "Settings · System · Config", { "reset", "default" }, edit(".config/hypr/hypridle.conf"))
  add(entries, "", "Hyprlock Config", "Settings · System · Config", { "reset", "default" }, edit(".config/hypr/hyprlock.conf"))
  add(entries, "", "Hyprsunset Config", "Settings · System · Config", { "reset", "default" }, edit(".config/hypr/hyprsunset.conf"))
  add(entries, "", "Swayosd Config", "Settings · System · Config", { "reset", "default" }, edit(".config/swayosd/config.toml"))
  add(entries, "󰌧", "Walker Config", "Settings · System · Config", { "reset", "default", "menu" }, edit(".config/walker/config.toml"))
  add(entries, "󰍜", "Waybar Config", "Settings · System · Config", { "reset", "default", "bar" }, edit(".config/waybar/config.jsonc"))
  add(entries, "󰞅", "XCompose Config", "Settings · System · Config", { "reset", "default", "input" }, edit(".XCompose"))

  -- Install-only software keeps its audited TUI/native presentation contract
  -- without inventing an Uninstall owner.
  add_software_installers(entries, "Settings · Software · Services")

  -- Appearance add-ons.
  add(entries, "", "Cascadia Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("font-cascadia-mono"))
  add(entries, "", "Meslo LG Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("font-meslo-mono"))
  add(entries, "", "Fira Code", "Settings · Appearance · Font", { "nerd font" }, install_font("font-fira-code"))
  add(entries, "", "Victor Code", "Settings · Appearance · Font", { "nerd font" }, install_font("font-victor-code"))
  add(entries, "", "Bitstream Vera Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("font-bitstream-vera"))
  add(entries, "", "Iosevka", "Settings · Appearance · Font", { "nerd font" }, install_font("font-iosevka"))

  add_software_installers(entries, "Settings · Software · Development")

  -- Editors, terminals, and AI.
  add_software_installers(entries, "Settings · Software · Editor")
  add_software_installers(entries, "Settings · Software · Terminal")
  add_software_installers(entries, "Settings · Software · AI")

  -- Restore and restart actions stay searchable under their owning object.
  add(entries, "", "Refresh Hyprland", "Settings · System · Config", { "default", "reset" }, task_action("refresh-hyprland"))
  add(entries, "", "Refresh Hypridle", "Settings · System · Config", { "default", "reset" }, task_action("refresh-hypridle"))
  add(entries, "", "Refresh Hyprlock", "Settings · System · Config", { "default", "reset" }, task_action("refresh-hyprlock"))
  add(entries, "", "Refresh Hyprsunset", "Settings · System · Config", { "default", "reset" }, task_action("refresh-hyprsunset"))
  add(entries, "󱣴", "Refresh Plymouth", "Settings · System · Config", { "default", "reset" }, task_action("refresh-plymouth"))
  add(entries, "", "Refresh Swayosd", "Settings · System · Config", { "default", "reset" }, task_action("refresh-swayosd"))
  add(entries, "", "Refresh Tmux", "Settings · System · Config", { "default", "reset" }, task_action("refresh-tmux"))
  add(entries, "󰌧", "Refresh Walker", "Settings · System · Config", { "default", "reset", "menu" }, task_action("refresh-walker"))
  add(entries, "󰍜", "Refresh Waybar", "Settings · System · Config", { "default", "reset", "bar" }, task_action("refresh-waybar"))
  add(entries, "", "Restart Hypridle", "Settings · System · Services", { "service", "reload" }, task_action("restart-hypridle"))
  add(entries, "", "Restart Hyprsunset", "Settings · System · Services", { "service", "reload" }, task_action("restart-hyprsunset"))
  add(entries, "󰎟", "Restart Mako", "Settings · System · Services", { "notifications", "reload" }, task_action("restart-mako"))
  add(entries, "", "Restart Swayosd", "Settings · System · Services", { "service", "reload" }, task_action("restart-swayosd"))
  add(entries, "󰌧", "Restart Walker", "Settings · System · Services", { "menu", "reload" }, task_action("restart-walker"))
  add(entries, "󰍜", "Restart Waybar", "Settings · System · Services", { "bar", "reload" }, task_action("restart-waybar"))
  add(entries, "", "Restart Audio", "Settings · Devices · Audio", { "pipewire", "sound" }, task_action("restart-audio"))
  add(entries, "󱚾", "Restart Wi-Fi", "Settings · Connections · Wi-Fi", { "network", "wifi" }, task_action("restart-wifi"))
  add(entries, "󰂯", "Restart Bluetooth", "Settings · Connections · Bluetooth", { "device", "network" }, task_action("restart-bluetooth"))
  add(entries, "󰟸", "Restart Trackpad", "Settings · Devices · Input", { "input", "device" }, task_action("restart-trackpad"))

  -- Power actions remain globally searchable without crowding Home.
  add(entries, "", "Lock", "More · Power", { "screen", "security" }, "omarchy-system-lock")
  add(entries, "󰒲", "Suspend", "More · Power", { "sleep", "power" }, "systemctl suspend")
  add(entries, "󰤁", "Hibernate", "More · Power", { "sleep", "power" }, "systemctl hibernate")
  add(entries, "󰍃", "Logout", "More · Power", { "session", "exit" }, "omarchy-system-logout")
  add(entries, "󰜉", "Restart", "More · Power", { "reboot", "power" }, "omarchy-system-reboot")
  add(entries, "󰐥", "Shutdown", "More · Power", { "power", "off" }, "omarchy-system-shutdown")

  return apply_search_intents(entries, query)
end
