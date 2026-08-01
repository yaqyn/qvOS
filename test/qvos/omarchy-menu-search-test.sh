#!/bin/bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
test_bin="$test_root/bin"
main_args_log="$test_root/main-args.log"
apps_args_log="$test_root/apps-args.log"
settings_options_log="$test_root/settings-options.log"
area_options_log="$test_root/area-options.log"
concept_options_log="$test_root/concept-options.log"
qvcore_options_log="$test_root/qvcore-options.log"
presentation_log="$test_root/presentation.log"
presentation_argv_log="$test_root/presentation-argv.log"
web_log="$test_root/web.log"
elephant_log="$test_root/elephant.log"
route_log="$test_root/route.log"
systemctl_log="$test_root/systemctl.log"

cleanup() {
  [[ -d $test_root ]] && rm -rf "$test_root"
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

install -d "$test_bin"
install -m 0755 /dev/stdin "$test_bin/systemctl" <<'SCRIPT'
#!/bin/bash
case $* in
"--user show-environment")
  printf 'HOME=%s\n' "$HOME"
  ;;
"--user is-active --quiet elephant.service" | \
"--user is-active --quiet app-walker@autostart.service")
  exit 0
  ;;
"--user restart elephant.service" | \
"--user restart app-walker@autostart.service")
  printf '%s\n' "$*" >>"$QVOS_TEST_SYSTEMCTL_LOG"
  ;;
esac
SCRIPT
install -d "$test_root/.config/elephant/menus"

HOME="$test_root" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  QVOS_TEST_SYSTEMCTL_LOG="$systemctl_log" \
  "$root/qv/menu/install" --install
HOME="$test_root" \
  OMARCHY_PATH="$root" \
  PATH="$test_bin:/usr/bin" \
  "$root/qv/menu/install" --status ||
  fail "installed menu status"
[[ $(<"$systemctl_log") == $'--user restart elephant.service\n--user restart app-walker@autostart.service' ]] ||
  fail "active menu service reload"
python3 - "$test_root/.config/walker/config.toml" <<'PY'
import pathlib
import sys
import tomllib

config = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
provider_set = config["providers"]["sets"]["qvos-omarchy-menu"]
assert config["theme"] == "qvos-omarchy-menu"
assert provider_set == {
    "default": ["menus:qvosOmarchyMenu"],
    "empty": ["menus:qvosOmarchyMenu"],
}

menu_actions = config["providers"]["actions"]["menus:qvosOmarchyMenu"]
assert any(
    action["action"] == "activate"
    and action["bind"] == "Return"
    and action["default"]
    for action in menu_actions
)
assert any(
    action["action"] == "show_apps"
    and action["bind"] == "Return"
    and action["default"]
    and action["after"] == "AsyncReload"
    for action in menu_actions
)
assert any(
    action["action"] == "show_menu"
    and action["bind"] == "Return"
    and action["default"]
    and action["after"] == "AsyncReload"
    for action in menu_actions
)
assert any(
    action["action"] == "toggle"
    and action["bind"] == "Tab"
    and action["label"] == "Apps / Menu"
    and action["after"] == "AsyncReload"
    for action in menu_actions
)
PY
pass "Walker binds Tab to a query-preserving mode reload"

menu_provider="$root/qv/menu/elephant/qvos_omarchy_menu.lua"
home_entries=$(
  OMARCHY_PATH="$test_root/missing" XDG_RUNTIME_DIR="$test_root" \
    lua - "$menu_provider" <<'LUA'
dofile(arg[1])
assert(Name == "qvosOmarchyMenu")
assert(Cache == false)
assert(FixedOrder == true)
assert(Actions.toggle == "lua:ToggleMode")
for _, entry in ipairs(GetEntries("")) do
  print(entry.Text)
end
LUA
)
[[ $home_entries == $'󰀻  All Apps\n󱅾  Update qvOS\n  Settings\n󰍜  More' ]] ||
  fail "four-item home catalog"
pass "empty search stays focused on four real destinations"

search_audit=$(
  HOME="$test_root" OMARCHY_PATH="$test_root/missing" \
    XDG_RUNTIME_DIR="$test_root" lua - "$menu_provider" <<'LUA'
dofile(arg[1])
local entries = GetEntries("all")
local concept_counts = {}
local concept_count = 0
local duplicate_counts = {}
local go_matches = 0
local proton_matches = 0
local style_matches = 0
local theme_matches = 0
local qvcore_matches = 0
local password_matches = 0
local old_breadcrumbs = 0

for line in io.lines(os.getenv("HOME") .. "/.local/share/qvos/menu/concepts.psv") do
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local slug, _, name, breadcrumb = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|")
    concept_counts[name] = {
      count = 0,
      route = "omarchy-menu 'concept:" .. slug .. "'",
      breadcrumb = breadcrumb,
    }
    concept_count = concept_count + 1
  end
end

for _, entry in ipairs(entries) do
  assert(entry.Text and entry.Text ~= "")
  assert(entry.Subtext and entry.Subtext ~= "")
  assert(entry.Actions and entry.Actions.activate and entry.Actions.activate ~= "")
  assert(not entry.Text:lower():find("separator", 1, true))

  local text = entry.Text:gsub("^.-  ", "")
  duplicate_counts[text] = (duplicate_counts[text] or 0) + 1
  if concept_counts[text] then
    concept_counts[text].count = concept_counts[text].count + 1
    assert(entry.Subtext == concept_counts[text].breadcrumb)
    assert(entry.Actions.activate == concept_counts[text].route)
  end
  if text == "Go" then
    go_matches = go_matches + 1
    assert(entry.Subtext == "Settings · Software · Development")
  end
  if text == "Proton" then
    proton_matches = proton_matches + 1
    assert(entry.Subtext == "Settings · Software · qvCORE")
  end
  if text == "Style" then
    style_matches = style_matches + 1
  end
  if text == "Theme" then
    theme_matches = theme_matches + 1
    assert(entry.Subtext == "Settings · Appearance")
  end
  if text == "qvCORE" then
    qvcore_matches = qvcore_matches + 1
    assert(entry.Subtext == "Settings · Software")
  end
  if text == "Password" then
    password_matches = password_matches + 1
    assert(entry.Subtext == "Settings · Security")
  end
  for _, obsolete in ipairs({ "Setup", "Install", "Remove", "Style", "Update", "Misc" }) do
    if entry.Subtext:find(obsolete, 1, true) then
      old_breadcrumbs = old_breadcrumbs + 1
    end
  end
end

for name, expected in pairs(concept_counts) do
  assert(expected.count == 1, name .. " should appear exactly once")
end

for name, count in pairs(duplicate_counts) do
  assert(count == 1, name .. " appears " .. count .. " times")
end

print(
  #entries,
  concept_count,
  go_matches,
  proton_matches,
  style_matches,
  theme_matches,
  qvcore_matches,
  password_matches,
  old_breadcrumbs
)
LUA
)
read -r search_count concept_count go_matches proton_matches style_matches theme_matches qvcore_matches password_matches old_breadcrumbs <<<"$search_audit"
((search_count >= 181)) || fail "global search catalog coverage"
((concept_count >= 73)) || fail "concept action catalog coverage"
((go_matches == 1)) || fail "single Go concept result"
((proton_matches == 1)) || fail "single Proton concept result"
((style_matches == 0)) || fail "Style verb folder removal"
((theme_matches == 1)) || fail "single Theme concept result"
((qvcore_matches == 1)) || fail "single qvCORE result"
((password_matches == 1)) || fail "single Password concept result"
((old_breadcrumbs == 0)) || fail "obsolete verb breadcrumbs"
pass "typed search presents every concept exactly once"

install_only_route_audit=$(
  HOME="$test_root" OMARCHY_PATH="$root" XDG_RUNTIME_DIR="$test_root" \
    lua - "$menu_provider" <<'LUA'
dofile(arg[1])

for _, entry in ipairs(GetEntries("sublime")) do
  if entry.Text:match("^.-  (.*)$") == "Sublime Text" then
    assert(entry.Subtext == "Settings · Software · Editor")
    assert(entry.Actions.activate:find(
      "/.local/share/qvos/tui/action/launch' '--installer' 'sublime-text'",
      1,
      true
    ))
    print("shared-tui")
    return
  end
end

error("Sublime Text installer is missing")
LUA
)
[[ $install_only_route_audit == "shared-tui" ]] ||
  fail "Sublime Text shared TUI installer route"
pass "install-only Software leaves use their audited qvOS action route"

software_action_audit=$(
  HOME="$test_root" OMARCHY_PATH="$test_root/missing" \
    XDG_RUNTIME_DIR="$test_root" lua - "$menu_provider" "$root" <<'LUA'
local real_popen = io.popen
io.popen = function(command)
  if command:find("software-state", 1, true) then
    local values = {
      "go\tuninstall",
      "rust\tinstall",
      "proton\tinstall",
    }
    local index = 0
    return {
      lines = function()
        return function()
          index = index + 1
          return values[index]
        end
      end,
      close = function() end,
    }
  end
  return real_popen(command)
end

dofile(arg[1])

local function by_name(entries, wanted)
  for _, entry in ipairs(entries) do
    if entry.Text:match("^.-  (.*)$") == wanted then
      return entry
    end
  end
end

local entries = GetEntries("software")
local go = assert(by_name(entries, "Go"))
local rust = assert(by_name(entries, "Rust"))
local proton = assert(by_name(entries, "Proton"))

assert(go.Subtext == "")
assert(rust.Subtext == "")
assert(proton.Subtext == "")
assert(go.Actions.activate:find("/.local/share/qvos/tui/action/launch' 'go'", 1, true))
assert(rust.Actions.activate:find("/.local/share/qvos/tui/action/launch' 'rust'", 1, true))

local view_file = assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/qvos-menu-view", "w"))
view_file:write("software\n")
view_file:close()
entries = GetEntries("")
local editor = assert(by_name(entries, "Editor"))
local package = assert(by_name(entries, "Package"))
assert(editor.Subtext == "")
assert(editor.Actions.activate == "omarchy-menu 'install-editor'")
assert(package.Subtext == "")
assert(package.Actions.activate == "omarchy-menu 'concept:package'")
assert(not by_name(entries, "Development"))

view_file = assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/qvos-menu-view", "w"))
view_file:write("software:development\n")
view_file:close()
entries = GetEntries("")
assert(by_name(entries, "Go"))
assert(by_name(entries, "Rust"))
assert(not by_name(entries, "Steam"))
view_file = assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/qvos-menu-view", "w"))
view_file:write("home\n")
view_file:close()
print(#entries)
LUA
)
((software_action_audit == 2)) ||
  fail "state-aware Software action coverage"
if rg -Fq '|Learn|' "$root/qv/menu/concepts.psv"; then
  fail "per-app Learn actions remain in the concept catalog"
fi
pass "software rows expose only names and delegate lifecycle to the TUI"

intent_audit=$(
  HOME="$test_root" OMARCHY_PATH="$test_root/missing" \
    XDG_RUNTIME_DIR="$test_root" lua - "$menu_provider" <<'LUA'
dofile(arg[1])

local function normalize(value)
  return value:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function entry_name(entry)
  return entry.Text:match("^.-  (.*)$") or entry.Text
end

local intent_path = os.getenv("HOME") .. "/.local/share/qvos/menu/search-intents.psv"
local seen_intents = {}
local target_counts = {}
local intent_count = 0
local required = {
  ["store"] = "Package",
  ["install"] = "Package",
  ["system update"] = "Update qvOS",
  ["volume mixer"] = "Audio",
  ["wifi settings"] = "Wi-Fi",
  ["warp"] = "DNS",
  ["display settings"] = "Monitors",
  ["keyboard shortcuts"] = "Keybindings",
  ["default apps"] = "Defaults",
  ["change password"] = "Password",
  ["developer tools"] = "Development",
  ["voice typing"] = "Dictation",
  ["send files"] = "Share",
  ["screen capture"] = "Screenshot",
  ["record screen"] = "Screenrecord",
  ["copy text from screen"] = "Text Extraction",
  ["do not disturb"] = "Notifications",
  ["blue light"] = "Nightlight",
  ["sign out"] = "Logout",
  ["power off"] = "Shutdown",
  ["proton docs"] = "Proton",
  ["battery protection"] = "Battery Protection",
  ["charging limit"] = "Battery Protection",
  ["battery conservation"] = "Battery Protection",
}

for line in io.lines(intent_path) do
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local intent, target = line:match("^([^|]+)|([^|]+)$")
    assert(intent and target, "invalid search intent: " .. line)

    local normalized = normalize(intent)
    assert(intent == normalized, "search intent is not normalized: " .. intent)
    assert(not seen_intents[normalized], "duplicate search intent: " .. intent)
    seen_intents[normalized] = target
    target_counts[target] = 0
    intent_count = intent_count + 1
  end
end

for _, entry in ipairs(GetEntries("all")) do
  local name = entry_name(entry)
  if target_counts[name] then
    target_counts[name] = target_counts[name] + 1
  end
end

for target, count in pairs(target_counts) do
  assert(count == 1, target .. " search target appears " .. count .. " times")
end

for intent, expected in pairs(required) do
  assert(seen_intents[intent] == expected, intent .. " should target " .. expected)
end

for _, ambiguous in ipairs({
  "browser",
  "cloud",
  "network",
  "password",
  "power",
  "screen",
  "settings",
  "sleep",
  "vpn",
}) do
  assert(not seen_intents[ambiguous], "ambiguous intent should stay fuzzy: " .. ambiguous)
end

for intent, expected in pairs(seen_intents) do
  local entries = GetEntries("  " .. intent:upper() .. "  ")
  assert(#entries == 1, intent .. " should return one exact intent")
  assert(entry_name(entries[1]) == expected, intent .. " returned the wrong target")

  local tagged = false
  for _, keyword in ipairs(entries[1].Keywords) do
    if keyword == intent then
      tagged = true
      break
    end
  end
  assert(tagged, intent .. " is missing from target keywords")
end

print(intent_count, #GetEntries("not-an-exact-intent"))
LUA
)
read -r intent_count fuzzy_catalog_count <<<"$intent_audit"
((intent_count >= 140)) || fail "high-value search intent coverage"
((fuzzy_catalog_count == search_count)) || fail "unmapped query keeps exhaustive fuzzy search"
pass "exact natural intents resolve once without claiming ambiguous words"

menu_agents="$root/qv/menu/AGENTS.md"
grep -Fq 'qv/menu/AGENTS.md' "$root/AGENTS.md" ||
  fail "root menu workflow route"
grep -Fqx '# qvOS Menu Workflow' "$menu_agents" ||
  fail "owner-local menu workflow heading"
grep -Fq 'Verbs are actions on one canonical concept' "$menu_agents" ||
  fail "canonical concept policy"
grep -Fq 'leave ambiguous words' "$menu_agents" ||
  fail "high-confidence search intent policy"
grep -Fq '<reviewed-upstream-sha>:bin/omarchy-menu' "$menu_agents" ||
  fail "qvsync upstream software source"
grep -Fq 'new, renamed, and removed software leaves' "$menu_agents" ||
  fail "qvsync software drift coverage"
grep -Fq 'Add a review-ledger row for each upstream leaf' "$menu_agents" ||
  fail "qvsync software reconciliation ledger"
grep -Fq 'independently for Install and Uninstall' "$menu_agents" ||
  fail "qvsync per-operation presentation review"
grep -Fq 'transitive helpers such as' "$menu_agents" ||
  fail "qvsync transitive sudo review"
grep -Fq 'invent an Uninstall owner from' "$menu_agents" ||
  fail "qvsync paired lifecycle boundary"
pass "owner-local AGENTS keeps the compact menu contract durable across qvsync"

apps_audit=$(
  HOME="$test_root" OMARCHY_PATH="$test_root/missing" \
    XDG_RUNTIME_DIR="$test_root" lua - "$menu_provider" <<'LUA'
local responses = {
  first = {
    item = {
      identifier = "code-oss.desktop",
      text = "Code - OSS",
      subtext = "Text Editor",
      icon = "com.visualstudio.code.oss",
    },
  },
  second = {
    item = {
      identifier = "codium.desktop",
      text = "VSCodium",
      icon = "vscodium",
    },
  },
  chromium = {
    item = {
      identifier = "chromium.desktop",
      text = "Chromium",
      subtext = "Web Browser",
      icon = "chromium",
    },
  },
}
local requested = ""

jsonDecode = function(line)
  return responses[line]
end

io.popen = function(command)
  requested = command
  local values = {}
  if command:find("desktopapplications;code;", 1, true) then
    values = { "first", "second" }
  elseif command:find("desktopapplications;chrom;", 1, true) then
    values = { "chromium" }
  end
  local index = 0
  return {
    lines = function()
      return function()
        index = index + 1
        return values[index]
      end
    end,
    close = function() end,
  }
end

dofile(arg[1])

ToggleMode()
local mode_file = assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/qvos-menu-mode", "r"))
assert(mode_file:read("*l") == "apps")
mode_file:close()

local entries = GetEntries("code")
assert(#entries == 2)
assert(entries[1].Text == "Code - OSS")
assert(entries[1].Icon == "com.visualstudio.code.oss")
assert(entries[1].Actions.activate == "elephant activate 'desktopapplications;code-oss.desktop;start;code;'")
assert(entries[2].Subtext == "Installed App")
assert(requested == "elephant query 'desktopapplications;code;256;false' --json 2>/dev/null")

ToggleMode()
mode_file = assert(io.open(os.getenv("XDG_RUNTIME_DIR") .. "/qvos-menu-mode", "r"))
assert(mode_file:read("*l") == "menu")
mode_file:close()

local menu_entries = GetEntries("code")
assert(#menu_entries > #entries)

ToggleMode()
local chromium = GetEntries("chrome")
assert(#chromium == 1)
assert(chromium[1].Text == "Chromium")
assert(chromium[1].Keywords[1] == "chrome")
assert(chromium[1].Actions.activate == "elephant activate 'desktopapplications;chromium.desktop;start;chrome;'")

ShowMenu()
ToggleMode()
local empty = GetEntries("zzzz")
assert(#empty == 1)
assert(empty[1].Text == "No installed app matches “zzzz”")
assert(empty[1].Actions.show_menu == "lua:ShowMenu")
ShowMenu()

print(#entries, #menu_entries, #chromium, #empty)
LUA
)
read -r installed_app_count returned_menu_count alias_count empty_count <<<"$apps_audit"
((installed_app_count == 2 && returned_menu_count == search_count && \
alias_count == 1 && empty_count == 1)) ||
  fail "query-preserving app and menu modes"
pass "the same query returns installed apps or menu concepts by mode"

cmp -s \
  "$root/default/walker/themes/omarchy-default/layout.xml" \
  "$test_root/.config/walker/themes/qvos-omarchy-menu/layout.xml" ||
  fail "menu theme inherits Walker layout"
[[ $(head -n 1 "$test_root/.config/walker/themes/qvos-omarchy-menu/style.css") == '@import "../../../omarchy/current/theme/walker.css";' ]] ||
  fail "menu theme import path"
grep -Fq 'font-size: 12px;' \
  "$test_root/.config/walker/themes/qvos-omarchy-menu/style.css" ||
  fail "menu breadcrumb typography"
grep -Fq '.elephant-hint {' \
  "$test_root/.config/walker/themes/qvos-omarchy-menu/style.css" ||
  fail "transient Elephant hint styling"
grep -Fq 'opacity: 0;' \
  "$root/qv/menu/walker-subtext.css" ||
  fail "transient Elephant hint suppression"
if grep -Fq 'font-size: 12px;' \
  "$root/default/walker/themes/omarchy-default/style.css"; then
  fail "qvOS menu typography drifted into inherited Walker source"
fi
pass "qvOS theme keeps breadcrumbs and hides transient provider noise"

cmp -s \
  "$root/qv/menu/wait-for-elephant" \
  "$test_root/.local/share/qvos/menu/wait-for-elephant" ||
  fail "Elephant readiness helper"
cmp -s \
  "$root/qv/menu/walker-elephant-ready.conf" \
  "$test_root/.config/systemd/user/app-walker@autostart.service.d/qvos-elephant-ready.conf" ||
  fail "Walker readiness drop-in"
grep -Fqx 'Wants=elephant.service' \
  "$root/qv/menu/walker-elephant-ready.conf" ||
  fail "Walker starts Elephant"
grep -Fqx 'After=elephant.service' \
  "$root/qv/menu/walker-elephant-ready.conf" ||
  fail "Walker starts after Elephant"

install -m 0755 /dev/stdin "$test_bin/elephant" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_ELEPHANT_LOG"
SCRIPT
QVOS_TEST_ELEPHANT_LOG="$elephant_log" \
  PATH="$test_bin:/usr/bin" \
  "$test_root/.local/share/qvos/menu/wait-for-elephant"
[[ $(<"$elephant_log") == "query providerlist;;1" ]] ||
  fail "Elephant provider readiness query"
pass "Walker startup waits for ready Elephant providers"

install -m 0755 /dev/stdin "$test_bin/pgrep" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-walker" <<'SCRIPT'
#!/bin/bash
case $* in
*"--set qvos-omarchy-menu"*)
  if [[ $(<"$XDG_RUNTIME_DIR/qvos-menu-mode") == "apps" ]]; then
    printf '%s\n' "$*" >"$QVOS_TEST_APPS_ARGS_LOG"
  else
    printf '%s\n' "$*" >"$QVOS_TEST_MAIN_ARGS_LOG"
  fi
  ;;
*"Settings…"*)
  cat >"$QVOS_TEST_SETTINGS_OPTIONS_LOG"
  printf '%s\n' "$QVOS_TEST_SETTINGS_CHOICE"
  ;;
*"Appearance…"* | *"Connections…"* | *"Devices…"* | *"Software…"* | *"System…"* | *"Security…"*)
  cat >"$QVOS_TEST_AREA_OPTIONS_LOG"
  printf '%s\n' "$QVOS_TEST_AREA_CHOICE"
  ;;
*"Go…"* | *"Proton…"* | *"Brave Origin…"* | *"Theme…"* | *"Password…"* | *"Wi-Fi…"* | *"Battery Protection…"*)
  cat >"$QVOS_TEST_CONCEPT_OPTIONS_LOG"
  printf '%s\n' "$QVOS_TEST_CONCEPT_CHOICE"
  ;;
*"qvCORE…"*)
  cat >"$QVOS_TEST_QVCORE_OPTIONS_LOG"
  printf '%s\n' "$QVOS_TEST_QVCORE_CHOICE"
  ;;
esac
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-floating-terminal-with-presentation" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_PRESENTATION_LOG"
printf '%s\n' "$@" >"$QVOS_TEST_PRESENTATION_ARGV_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/omarchy-launch-webapp" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$QVOS_TEST_WEB_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qvos-software-action" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$1" >"$QVOS_TEST_PRESENTATION_LOG"
SCRIPT

install -m 0755 /dev/stdin "$test_bin/qvos-tui-task" <<'SCRIPT'
#!/bin/bash
awk -F '|' -v wanted="$1" '
  $1 !~ /^#/ && NF == 11 && $1 == wanted {
    print $11
    found = 1
    exit
  }
  END { exit !found }
' "$OMARCHY_PATH/qv/tui/task/actions.psv" >"$QVOS_TEST_PRESENTATION_LOG"
SCRIPT

for command_name in \
  omarchy-launch-audio \
  omarchy-launch-wifi \
  omarchy-launch-bluetooth; do
  install -m 0755 /dev/stdin "$test_bin/$command_name" <<'SCRIPT'
#!/bin/bash
basename -- "$0" >"$QVOS_TEST_ROUTE_LOG"
SCRIPT
done

run_menu() {
  QVOS_TEST_MAIN_ARGS_LOG="$main_args_log" \
    QVOS_TEST_APPS_ARGS_LOG="$apps_args_log" \
    QVOS_TEST_SETTINGS_OPTIONS_LOG="$settings_options_log" \
    QVOS_TEST_SETTINGS_CHOICE="${QVOS_TEST_SETTINGS_CHOICE:-}" \
    QVOS_TEST_AREA_OPTIONS_LOG="$area_options_log" \
    QVOS_TEST_AREA_CHOICE="${QVOS_TEST_AREA_CHOICE:-}" \
    QVOS_TEST_CONCEPT_OPTIONS_LOG="$concept_options_log" \
    QVOS_TEST_CONCEPT_CHOICE="${QVOS_TEST_CONCEPT_CHOICE:-}" \
    QVOS_TEST_QVCORE_OPTIONS_LOG="$qvcore_options_log" \
    QVOS_TEST_QVCORE_CHOICE="${QVOS_TEST_QVCORE_CHOICE:-}" \
    QVOS_TEST_PRESENTATION_LOG="$presentation_log" \
    QVOS_TEST_PRESENTATION_ARGV_LOG="$presentation_argv_log" \
    QVOS_TEST_WEB_LOG="$web_log" \
    QVOS_TEST_ROUTE_LOG="$route_log" \
    QVOS_SOFTWARE_ACTION_LAUNCH="$test_bin/qvos-software-action" \
    QVOS_TUI_TASK_LAUNCH="$test_bin/qvos-tui-task" \
    HOME="$test_root" \
    XDG_RUNTIME_DIR="$test_root" \
    OMARCHY_PATH="$root" \
    PATH="$test_bin:$root/bin:/usr/bin" \
    "$root/bin/omarchy-menu" "$@"
}

run_menu
grep -Fq -- '--theme qvos-omarchy-menu' "$main_args_log" ||
  fail "dedicated menu theme"
grep -Fq -- '--set qvos-omarchy-menu' "$main_args_log" ||
  fail "global search provider set"
grep -Fq -- 'Tab: Apps ↔ Menu' "$main_args_log" ||
  fail "menu switch affordance"
run_menu apps
grep -Fq -- '--theme qvos-omarchy-menu' "$apps_args_log" ||
  fail "All Apps transient hint suppression"
grep -Fq -- '--set qvos-omarchy-menu' "$apps_args_log" ||
  fail "shared query provider"
grep -Fq -- 'Tab: Apps ↔ Menu' "$apps_args_log" ||
  fail "apps switch affordance"
[[ $(<"$test_root/qvos-menu-mode") == "apps" ]] ||
  fail "Apps launch mode"
pass "Omarchy and Apps share one query-preserving Walker surface"

run_menu concept:go
[[ $(<"$presentation_log") == "go" ]] ||
  fail "Go concept direct action"
run_menu concept:proton
[[ $(<"$presentation_log") == "proton" ]] ||
  fail "Proton concept direct action"
run_menu concept:brave-origin
[[ $(<"$presentation_log") == "brave-origin" ]] ||
  fail "Brave Origin concept direct action"

: >"$concept_options_log"
run_menu concept:development
[[ $(<"$test_root/qvos-menu-view") == "software:development" ]] ||
  fail "Development concept direct browse"
[[ ! -s $concept_options_log ]] ||
  fail "Development concept has a redundant action sheet"

single_action_routes=$(
  HOME="$test_root" OMARCHY_PATH="$root" bash -s -- \
    "$root/qv/menu/extension.sh" <<'SCRIPT'
set -euo pipefail

source "$1"

active_slug=""

menu() {
  printf 'unexpected concept sheet for %s\n' "$active_slug" >&2
  return 97
}

run_concept_action() {
  printf '%s|%s\n' "$active_slug" "$1"
}

while IFS= read -r line || [[ -n $line ]]; do
  [[ -z $line || $line == \#* ]] && continue
  IFS='|' read -r -a fields <<<"$line"
  action_count=0

  for ((index = 5; index + 1 < ${#fields[@]}; index += 2)); do
    if [[ -n ${fields[$index]} && -n ${fields[$((index + 1))]} ]]; then
      ((action_count += 1))
    fi
  done

  if ((action_count == 1)); then
    active_slug=${fields[0]}
    show_concept_menu "$active_slug"
  fi
done <"$HOME/.local/share/qvos/menu/concepts.psv"
SCRIPT
)
expected_single_action_routes=$(
  awk -F '|' '
    $1 !~ /^#/ && NF >= 7 {
      action_count = 0
      action = ""
      for (field = 6; field <= NF; field += 2) {
        if ($field != "" && $(field + 1) != "") {
          action_count++
          action = $(field + 1)
        }
      }
      if (action_count == 1) {
        print $1 "|" action
      }
    }
  ' "$root/qv/menu/concepts.psv"
)
[[ $single_action_routes == "$expected_single_action_routes" ]] ||
  fail "all one-action concepts activate directly"
pass "all one-action concepts skip redundant action sheets"

QVOS_TEST_CONCEPT_CHOICE=Install run_menu concept:theme
[[ $(<"$concept_options_log") == $'󰄬  Choose\n󰐕  Install\n󰆴  Remove\n󱅾  Update' ]] ||
  fail "Theme concept actions"
[[ $(<"$presentation_log") == "omarchy-theme-install" ]] ||
  fail "Theme install owner"
QVOS_TEST_CONCEPT_CHOICE=Remove run_menu concept:theme
[[ $(<"$presentation_log") == "qv/tui/task/selectable-owner theme-remove" ]] ||
  fail "Theme remove owner"
QVOS_TEST_CONCEPT_CHOICE=Update run_menu concept:theme
[[ $(<"$presentation_log") == "omarchy-theme-update" ]] ||
  fail "Theme update owner"

QVOS_TEST_CONCEPT_CHOICE="Drive Encryption" run_menu concept:password
[[ $(<"$concept_options_log") == $'  User\n󰌾  Drive Encryption' ]] ||
  fail "Password concept actions"
[[ $(<"$presentation_log") == "omarchy-drive-password" ]] ||
  fail "Drive Encryption password owner"

QVOS_TEST_CONCEPT_CHOICE=Report run_menu concept:battery-protection
[[ $(<"$concept_options_log") == $'󰋼  Status\n󰐕  Enable\n󰆴  Disable\n󰂄  Full Charge Once\n󰈙  Report' ]] ||
  fail "Battery Protection concept actions"
[[ $(<"$presentation_log") == "omarchy battery protection report" ]] ||
  fail "Battery Protection native report owner"
[[ $(<"$presentation_argv_log") == $'omarchy\nbattery\nprotection\nreport' ]] ||
  fail "Battery Protection native report argument boundaries"
pass "concept sheets delegate their named actions correctly"

QVOS_TEST_SETTINGS_CHOICE=Appearance run_menu settings
[[ $(<"$settings_options_log") == $'  Appearance\n󰖩  Connections\n󰋊  Devices\n󰏖  Software\n󰒓  System\n  Security' ]] ||
  fail "six-area Settings menu"
grep -Fqx '󰸌  Theme' "$area_options_log" || fail "Theme appearance item"
grep -Fqx '󱄄  Screensaver' "$area_options_log" || fail "Screensaver appearance item"
if grep -Eq '(^|  )(Install|Remove|Style|Update)$' "$settings_options_log" "$area_options_log"; then
  fail "verb folder in Settings browse"
fi

QVOS_TEST_SETTINGS_CHOICE=Software run_menu settings
[[ $(<"$test_root/qvos-menu-view") == "software" ]] ||
  fail "Software opens the focused Elephant view"
grep -Fq -- 'Search software…' "$main_args_log" ||
  fail "Software view search affordance"

: >"$route_log"
QVOS_TEST_SETTINGS_CHOICE=Connections \
  QVOS_TEST_AREA_CHOICE=Wi-Fi \
  QVOS_TEST_CONCEPT_CHOICE=Open \
  run_menu settings
[[ $(<"$route_log") == "omarchy-launch-wifi" ]] ||
  fail "Wi-Fi concept owner"
[[ $(<"$area_options_log") == $'  Wi-Fi\n󰂯  Bluetooth\n󰐕  DNS' ]] ||
  fail "catalog-derived Connections menu"

QVOS_TEST_SETTINGS_CHOICE=System \
  QVOS_TEST_AREA_CHOICE="Battery Protection" \
  QVOS_TEST_CONCEPT_CHOICE=Status \
  run_menu settings
grep -Fqx '󰁹  Battery Protection' "$area_options_log" ||
  fail "Battery Protection System concept"
[[ $(<"$presentation_log") == "omarchy battery protection status" ]] ||
  fail "Battery Protection native status route"
pass "Settings browse is shallow, noun-based, and catalog-derived"
