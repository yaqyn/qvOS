Name = "qvosOmarchyMenu"
NamePretty = "Omarchy"
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

local function present(command)
  return "omarchy-launch-floating-terminal-with-presentation " .. command
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

local function install_package(name, packages)
  local command = "echo "
    .. shell_escape("Installing " .. name .. "...")
    .. "; omarchy-pkg-add "
    .. packages
  return present("bash -lc " .. shell_escape(command))
end

local function install_and_launch(name, packages, desktop)
  local command = "echo "
    .. shell_escape("Installing " .. name .. "...")
    .. "; omarchy-pkg-add "
    .. packages
    .. " && setsid gtk-launch "
    .. desktop
  return present("bash -lc " .. shell_escape(command))
end

local function install_font(name, packages, font)
  local command = "echo "
    .. shell_escape("Installing " .. name .. "...")
    .. "; omarchy-pkg-add "
    .. packages
    .. " && sleep 2 && omarchy-font-set "
    .. shell_escape(font)
  return present("bash -lc " .. shell_escape(command))
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

local function add_concepts(entries)
  local home = os.getenv("HOME")
  local catalog = home and io.open(home .. "/.local/share/qvos/menu/concepts.psv", "r")

  if not catalog then
    return
  end

  for line in catalog:lines() do
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local fields = split(line, "|")
      add(
        entries,
        fields[2],
        fields[3],
        fields[4],
        split(fields[5], ","),
        route("concept:" .. fields[1])
      )
    end
  end

  catalog:close()
end

function GetEntries(query)
  query = query or ""

  if read_mode() == "apps" then
    return app_entries(query)
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
  add(entries, "", "Omarchy Manual", "More · Learn", { "docs", "help" }, "omarchy-launch-webapp https://learn.omacom.io/2/the-omarchy-manual")
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
  add(entries, "", "Direct Boot", "More · Toggles", { "limine", "boot" }, present("omarchy-config-direct-boot"))
  add(entries, "󰛧", "Laptop Display", "Settings · Devices", { "monitor", "toggle" }, "omarchy-hyprland-monitor-internal toggle")
  add(entries, "󰍹", "Mirror Display", "Settings · Devices", { "monitor", "toggle" }, "omarchy-hyprland-monitor-internal-mirror toggle")
  add(entries, "", "Hybrid GPU", "Settings · Devices", { "graphics", "toggle" }, present("omarchy-toggle-hybrid-gpu"))
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

  -- Install services.
  add(entries, "", "Dropbox", "Settings · Software · Services", { "cloud", "storage" }, present("omarchy-install-dropbox"))
  add(entries, "", "Tailscale", "Settings · Software · Services", { "vpn", "network" }, present("omarchy-install-tailscale"))
  add(entries, "󱇱", "NordVPN", "Settings · Software · Services", { "aur", "vpn" }, present("omarchy-install-nordvpn"))
  add(entries, "󰏖", "ONCE", "Settings · Software · Services", { "37signals", "server" }, present("omarchy-install-once"))
  add(entries, "󰟵", "Bitwarden", "Settings · Software · Services", { "password", "vault" }, install_and_launch("Bitwarden", "bitwarden bitwarden-cli", "bitwarden"))
  add(entries, "", "Chromium Account", "Settings · Software · Services", { "google", "sync" }, present("omarchy-install-chromium-google-account"))

  -- Appearance add-ons.
  add(entries, "", "Cascadia Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("Cascadia Mono", "ttf-cascadia-mono-nerd", "CaskaydiaMono Nerd Font"))
  add(entries, "", "Meslo LG Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("Meslo LG Mono", "ttf-meslo-nerd", "MesloLGL Nerd Font"))
  add(entries, "", "Fira Code", "Settings · Appearance · Font", { "nerd font" }, install_font("Fira Code", "ttf-firacode-nerd", "FiraCode Nerd Font"))
  add(entries, "", "Victor Code", "Settings · Appearance · Font", { "nerd font" }, install_font("Victor Code", "ttf-victor-mono-nerd", "VictorMono Nerd Font"))
  add(entries, "", "Bitstream Vera Mono", "Settings · Appearance · Font", { "nerd font" }, install_font("Bitstream Vera Code", "ttf-bitstream-vera-mono-nerd", "BitstromWera Nerd Font"))
  add(entries, "", "Iosevka", "Settings · Appearance · Font", { "nerd font" }, install_font("Iosevka", "ttf-iosevka-nerd", "Iosevka Nerd Font Mono"))

  add(entries, "", "Docker DB", "Settings · Software · Development", { "database", "container" }, present("omarchy-install-docker-dbs"))

  -- Editors, terminals, and AI.
  add(entries, "", "VSCode", "Settings · Software · Editor", { "code", "ide" }, present("omarchy-install-vscode"))
  add(entries, "", "Cursor", "Settings · Software · Editor", { "code", "ide", "ai" }, install_and_launch("Cursor", "cursor-bin", "cursor"))
  add(entries, "", "Zed", "Settings · Software · Editor", { "code", "ide" }, present("omarchy-install-zed"))
  add(entries, "", "Sublime Text", "Settings · Software · Editor", { "code", "ide" }, install_and_launch("Sublime Text", "sublime-text-4", "sublime_text"))
  add(entries, "", "Helix", "Settings · Software · Editor", { "code", "terminal" }, present("omarchy-install-helix"))
  add(entries, "", "Vim", "Settings · Software · Editor", { "code", "terminal" }, install_package("Vim", "vim"))
  add(entries, "", "Emacs", "Settings · Software · Editor", { "code", "ide" }, present("bash -lc " .. shell_escape("echo 'Installing Emacs...'; omarchy-pkg-add emacs-wayland && systemctl --user enable --now emacs.service")))
  add(entries, "", "Alacritty", "Settings · Software · Terminal", { "shell", "console" }, present("omarchy-install-terminal alacritty"))
  add(entries, "", "Foot", "Settings · Software · Terminal", { "shell", "console" }, present("omarchy-install-terminal foot"))
  add(entries, "", "Ghostty", "Settings · Software · Terminal", { "shell", "console" }, present("omarchy-install-terminal ghostty"))
  add(entries, "", "Kitty", "Settings · Software · Terminal", { "shell", "console" }, present("omarchy-install-terminal kitty"))
  add(entries, "󱚤", "LM Studio", "Settings · Software · AI", { "llm", "local" }, install_package("LM Studio", "lmstudio-bin"))
  add(entries, "󱚤", "Ollama", "Settings · Software · AI", { "llm", "local" }, route("install-ai"))
  add(entries, "󱚤", "Crush", "Settings · Software · AI", { "agent", "terminal" }, install_package("Crush", "crush-bin"))

  -- Restore and restart actions stay searchable under their owning object.
  add(entries, "", "Refresh Hyprland", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-hyprland"))
  add(entries, "", "Refresh Hypridle", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-hypridle"))
  add(entries, "", "Refresh Hyprlock", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-hyprlock"))
  add(entries, "", "Refresh Hyprsunset", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-hyprsunset"))
  add(entries, "󱣴", "Refresh Plymouth", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-plymouth"))
  add(entries, "", "Refresh Swayosd", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-swayosd"))
  add(entries, "", "Refresh Tmux", "Settings · System · Config", { "default", "reset" }, present("omarchy-refresh-tmux"))
  add(entries, "󰌧", "Refresh Walker", "Settings · System · Config", { "default", "reset", "menu" }, present("omarchy-refresh-walker"))
  add(entries, "󰍜", "Refresh Waybar", "Settings · System · Config", { "default", "reset", "bar" }, present("omarchy-qvos-refresh-waybar"))
  add(entries, "", "Restart Hypridle", "Settings · System · Services", { "service", "reload" }, "omarchy-restart-hypridle")
  add(entries, "", "Restart Hyprsunset", "Settings · System · Services", { "service", "reload" }, "omarchy-restart-hyprsunset")
  add(entries, "󰎟", "Restart Mako", "Settings · System · Services", { "notifications", "reload" }, "omarchy-restart-mako")
  add(entries, "", "Restart Swayosd", "Settings · System · Services", { "service", "reload" }, "omarchy-restart-swayosd")
  add(entries, "󰌧", "Restart Walker", "Settings · System · Services", { "menu", "reload" }, "omarchy-restart-walker")
  add(entries, "󰍜", "Restart Waybar", "Settings · System · Services", { "bar", "reload" }, "omarchy-restart-waybar")
  add(entries, "", "Restart Audio", "Settings · Devices · Audio", { "pipewire", "sound" }, present("omarchy-restart-pipewire"))
  add(entries, "󱚾", "Restart Wi-Fi", "Settings · Connections · Wi-Fi", { "network", "wifi" }, present("omarchy-restart-wifi"))
  add(entries, "󰂯", "Restart Bluetooth", "Settings · Connections · Bluetooth", { "device", "network" }, present("omarchy-restart-bluetooth"))
  add(entries, "󰟸", "Restart Trackpad", "Settings · Devices · Input", { "input", "device" }, present("omarchy-restart-trackpad"))

  -- Power actions remain globally searchable without crowding Home.
  add(entries, "", "Lock", "More · Power", { "screen", "security" }, "omarchy-system-lock")
  add(entries, "󰒲", "Suspend", "More · Power", { "sleep", "power" }, "systemctl suspend")
  add(entries, "󰤁", "Hibernate", "More · Power", { "sleep", "power" }, "systemctl hibernate")
  add(entries, "󰍃", "Logout", "More · Power", { "session", "exit" }, "omarchy-system-logout")
  add(entries, "󰜉", "Restart", "More · Power", { "reboot", "power" }, "omarchy-system-reboot")
  add(entries, "󰐥", "Shutdown", "More · Power", { "power", "off" }, "omarchy-system-shutdown")

  return apply_search_intents(entries, query)
end
