# shellcheck shell=bash

# qvOS menu overrides loaded before personal Omarchy menu extensions.

INSTALL_EASY_LIST_ACTIVE=false
STYLE_BACK_MENU=show_main_menu

launch_tui_task() {
  local launcher=${QVOS_TUI_TASK_LAUNCH:-${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/tui/task/launch}

  "$launcher" "$1"
}

tui_task_for_owner() {
  local owner_command="$1"
  local catalog="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/tui/task/actions.psv"

  awk -F '|' -v wanted="$owner_command" '
    $1 !~ /^#/ && NF == 11 && $11 == wanted {
      print $1
      found = 1
      exit
    }
    END { exit !found }
  ' "$catalog"
}

present_terminal() {
  local owner_command="$*"
  local task

  if task=$(tui_task_for_owner "$owner_command"); then
    launch_tui_task "$task"
  else
    omarchy-launch-floating-terminal-with-presentation "$owner_command"
  fi
}

set_qvos_menu_mode() {
  local mode="$1"
  local runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$UID}

  [[ $mode == "menu" || $mode == "apps" ]] || return 2
  printf '%s\n' "$mode" >"$runtime_dir/qvos-menu-mode"
}

set_qvos_menu_view() {
  local view="$1"
  local runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$UID}

  [[ $view == "home" || $view == "software" || $view == software:* ]] || return 2
  printf '%s\n' "$view" >"$runtime_dir/qvos-menu-view"
}

show_main_menu() {
  set_qvos_menu_mode menu
  set_qvos_menu_view home
  omarchy-launch-walker \
    --theme qvos-omarchy-menu \
    --set qvos-omarchy-menu \
    --width 560 \
    --minheight 1 \
    --maxheight 630 \
    --placeholder "Search…  ·  Tab: Apps ↔ Menu"
}

show_settings_menu() {
  case $(menu "Settings" "  Appearance\n󰖩  Connections\n󰋊  Devices\n󰏖  Software\n󰒓  System\n  Security") in
  *Appearance*) show_settings_area_menu "Appearance" ;;
  *Connections*) show_settings_area_menu "Connections" ;;
  *Devices*) show_settings_area_menu "Devices" ;;
  *Software*) show_settings_area_menu "Software" ;;
  *System*) show_settings_area_menu "System" ;;
  *Security*) show_settings_area_menu "Security" ;;
  *) back_to show_main_menu ;;
  esac
}

show_settings_area_menu() {
  local area="$1"
  local catalog="$HOME/.local/share/qvos/menu/concepts.psv"
  local line
  local choice
  local index
  local options=""
  local -a fields=()
  local -a names=()
  local -a slugs=()

  if [[ $area == "Software" ]]; then
    show_software_menu
    return
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    IFS='|' read -r -a fields <<<"$line"
    [[ ${fields[3]:-} == "Settings · $area" ]] || continue

    slugs+=("${fields[0]}")
    names+=("${fields[2]}")
    options="${options:+$options\n}${fields[1]}  ${fields[2]}"
  done <"$catalog"

  choice=$(menu "$area" "$options")
  choice=${choice#*  }

  for index in "${!names[@]}"; do
    if [[ $choice == "${names[$index]}" ]]; then
      show_concept_menu "${slugs[$index]}" "$area"
      return
    fi
  done

  back_to show_settings_menu
}

show_settings_software_menu() {
  show_software_menu
}

show_software_menu() {
  local group=${1:-}
  local view="software"

  [[ -z $group ]] || view="software:$group"
  set_qvos_menu_mode menu
  set_qvos_menu_view "$view"
  omarchy-launch-walker \
    --theme qvos-omarchy-menu \
    --set qvos-omarchy-menu \
    --width 560 \
    --minheight 1 \
    --maxheight 630 \
    --placeholder "Search software…"
}

launch_software_action() {
  local launcher=${QVOS_SOFTWARE_ACTION_LAUNCH:-${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/tui/action/launch}

  "$launcher" "$1"
}

launch_software_installer() {
  local launcher=${QVOS_SOFTWARE_INSTALLER_LAUNCH:-${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/tui/action/launch}

  "$launcher" --installer "$1"
}

show_install_font_menu() {
  case $(menu "Install" "  Cascadia Mono\n  Meslo LG Mono\n  Fira Code\n  Victor Code\n  Bitstream Vera Mono\n  Iosevka" "--width 350") in
  *Cascadia*) launch_software_installer font-cascadia-mono ;;
  *Meslo*) launch_software_installer font-meslo-mono ;;
  *Fira*) launch_software_installer font-fira-code ;;
  *Victor*) launch_software_installer font-victor-code ;;
  *Bitstream*) launch_software_installer font-bitstream-vera ;;
  *Iosevka*) launch_software_installer font-iosevka ;;
  *) show_install_menu ;;
  esac
}

show_software_installer_menu() {
  local breadcrumb="$1"
  local catalog="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/menu/software-installers.psv"
  local slug
  local icon
  local name
  local entry_breadcrumb
  local extra
  local choice
  local index
  local options=""
  local -a slugs=()
  local -a names=()

  if [[ $breadcrumb == "Settings · Software · AI" ]]; then
    slugs+=(dictation)
    names+=(Dictation)
    options="  Dictation"
  fi

  while IFS='|' read -r \
    slug \
    icon \
    name \
    entry_breadcrumb \
    _ \
    _ \
    _ \
    _ \
    _ \
    _ \
    _ \
    extra; do
    [[ -n $slug && $slug != "#"* ]] || continue
    [[ $entry_breadcrumb == "$breadcrumb" && -z ${extra:-} ]] || continue
    slugs+=("$slug")
    names+=("$name")
    options="${options:+$options\n}$icon  $name"
  done <"$catalog"

  choice=$(menu "Install" "$options")
  choice=${choice#*  }
  for index in "${!names[@]}"; do
    [[ $choice == "${names[$index]}" ]] || continue
    if [[ ${slugs[$index]} == "dictation" ]]; then
      launch_software_action dictation
    else
      launch_software_installer "${slugs[$index]}"
    fi
    return
  done

  show_install_menu
}

show_install_service_menu() {
  show_software_installer_menu "Settings · Software · Services"
}

show_install_editor_menu() {
  show_software_installer_menu "Settings · Software · Editor"
}

show_install_terminal_menu() {
  show_software_installer_menu "Settings · Software · Terminal"
}

show_install_ai_menu() {
  show_software_installer_menu "Settings · Software · AI"
}

show_install_development_menu() {
  show_software_menu development
}

show_install_javascript_menu() {
  show_software_menu javascript
}

show_install_browser_menu() {
  show_software_menu browser
}

show_install_gaming_menu() {
  show_software_menu gaming
}

show_remove_development_menu() {
  show_software_menu development
}

show_remove_browser_menu() {
  show_software_menu browser
}

show_remove_gaming_menu() {
  show_software_menu gaming
}

show_more_menu() {
  case $(menu "More" "󰧑  Learn\n  Capture\n  Share\n󰔛  Reminder\n󰔎  Toggles\n  About\n  Power") in
  *Learn*) show_learn_menu ;;
  *Capture*) show_capture_menu ;;
  *Share*) show_concept_menu share ;;
  *Reminder*) show_reminder_menu ;;
  *Toggles*) show_toggle_menu ;;
  *About*) show_about ;;
  *Power*) show_system_menu ;;
  *) back_to show_main_menu ;;
  esac
}

run_concept_action() {
  local action="$1"

  case $action in
  present:*) present_terminal "${action#present:}" ;;
  menu:*) go_to_menu "${action#menu:}" ;;
  run:*) bash -lc "${action#run:}" ;;
  terminal:*) terminal bash -lc "${action#terminal:}" ;;
  web:*) omarchy-launch-webapp "${action#web:}" ;;
  edit:*) open_in_editor "$HOME/${action#edit:}" ;;
  *)
    notify-send "This menu action is unavailable"
    return 1
    ;;
  esac
}

concept_action_icon() {
  case $1 in
  Open) printf '󰏌' ;;
  Browse) printf '󰈈' ;;
  Install) printf '󰐕' ;;
  AUR) printf '󰣇' ;;
  Remove) printf '󰆴' ;;
  Learn) printf '󰧑' ;;
  Choose) printf '󰄬' ;;
  View) printf '󰈈' ;;
  Status) printf '󰋼' ;;
  Enable) printf '󰐕' ;;
  Disable) printf '󰆴' ;;
  "Full Charge Once") printf '󰂄' ;;
  Report) printf '󰈙' ;;
  Edit) printf '' ;;
  "Edit Text") printf '' ;;
  "Set Image") printf '' ;;
  Restore) printf '' ;;
  Update) printf '󱅾' ;;
  Configure) printf '' ;;
  "Set Up") printf '' ;;
  User) printf '' ;;
  "Drive Encryption") printf '󰌾' ;;
  Timezone) printf '' ;;
  Sync) printf '' ;;
  Setup) printf '' ;;
  Control) printf '󰒓' ;;
  Restart) printf '󰜉' ;;
  Send) printf '' ;;
  Start) printf '' ;;
  Toggle) printf '󰔎' ;;
  Style) printf '' ;;
  *) printf '›' ;;
  esac
}

show_concept_menu() {
  local slug="$1"
  local back_area="${2:-}"
  local catalog="$HOME/.local/share/qvos/menu/concepts.psv"
  local line
  local -a fields=()
  local -a labels=()
  local -a actions=()
  local name=""
  local choice
  local icon
  local index
  local options=""

  if awk -F '|' -v wanted="$slug" '
    $1 !~ /^#/ && NF == 9 && $1 == wanted { found = 1 }
    END { exit !found }
  ' "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/menu/software-actions.psv"; then
    launch_software_action "$slug"
    return
  fi

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    IFS='|' read -r -a fields <<<"$line"
    [[ ${fields[0]:-} == "$slug" ]] || continue

    name=${fields[2]:-}
    for ((index = 5; index + 1 < ${#fields[@]}; index += 2)); do
      if [[ -n ${fields[$index]} && -n ${fields[$((index + 1))]} ]]; then
        labels+=("${fields[$index]}")
        actions+=("${fields[$((index + 1))]}")
      fi
    done
    break
  done <"$catalog"

  if [[ -z $name ]]; then
    notify-send "This menu item is unavailable" "$slug"
    return 1
  fi

  if ((${#actions[@]} == 0)); then
    notify-send "This menu item has no available actions" "$name"
    return 1
  fi

  if ((${#actions[@]} == 1)); then
    run_concept_action "${actions[0]}"
    return
  fi

  for index in "${!labels[@]}"; do
    icon=$(concept_action_icon "${labels[$index]}")
    options="${options:+$options\n}$icon  ${labels[$index]}"
  done

  choice=$(menu "$name" "$options")
  choice=${choice#*  }

  for index in "${!labels[@]}"; do
    if [[ $choice == "${labels[$index]}" ]]; then
      run_concept_action "${actions[$index]}"
      return
    fi
  done

  if [[ -n $back_area ]]; then
    show_settings_area_menu "$back_area"
  else
    back_to show_main_menu
  fi
}

show_trigger_menu() {
  local options="󰔛  Reminder\n  Capture\n󰧸  Transcode"
  omarchy-cmd-present localsend && options="$options\n  Share"
  options="$options\n󰔎  Toggle\n  Hardware"

  case $(menu "Trigger" "$options") in
  *Reminder*) show_reminder_menu ;;
  *Capture*) show_capture_menu ;;
  *Transcode*) omarchy-transcode || back_to show_trigger_menu ;;
  *Share*) show_share_menu ;;
  *Toggle*) show_toggle_menu ;;
  *Hardware*) show_hardware_menu ;;
  *) show_main_menu ;;
  esac
}

show_share_menu() {
  if omarchy-cmd-missing localsend; then
    notify-send "LocalSend is not installed" -t 2000
    back_to show_trigger_menu
    return
  fi

  case $(menu "Share" "  Clipboard\n  File \n  Folder") in
  *Clipboard*) omarchy-qvos-share clipboard ;;
  *File*) terminal bash -c "omarchy-qvos-share file" ;;
  *Folder*) terminal bash -c "omarchy-qvos-share folder" ;;
  *) back_to show_trigger_menu ;;
  esac
}

show_style_menu() {
  case $(menu "Style" "󰸌  Theme\n󰟵  Unlock\n  Font\n  Background\n  Hyprland\n󱄄  Screensaver\n  About") in
  *Theme*) show_theme_menu ;;
  *Unlock*) omarchy-launch-walker -m menus:omarchyunlocks --width 800 --minheight 400 ;;
  *Font*) show_font_menu ;;
  *Background*) show_background_menu ;;
  *Hyprland*) open_in_editor ~/.config/hypr/looknfeel.conf ;;
  *Screensaver*) show_screensaver_menu ;;
  *About*) show_about_menu ;;
  *) "$STYLE_BACK_MENU" ;;
  esac
}

show_setup_menu() {
  local options="  Audio\n  Wi-Fi\n󰂯  Bluetooth\n󱐋  Power Profile\n  System Sleep\n󰍹  Monitors"
  [[ -f ~/.config/hypr/bindings.conf ]] && options="$options\n  Keybindings"
  [[ -f ~/.config/hypr/input.conf ]] && options="$options\n  Input"
  options="$options\n  Defaults\n󰐕  DNS\n  Security\n  Config"

  case $(menu "Setup" "$options") in
  *Audio*) omarchy-launch-audio ;;
  *Wi-Fi*) omarchy-launch-wifi ;;
  *Bluetooth*) omarchy-launch-bluetooth ;;
  *Power*) show_setup_power_menu ;;
  *System*) show_setup_system_menu ;;
  *Monitors*) open_in_editor ~/.config/hypr/monitors.conf ;;
  *Keybindings*) open_in_editor ~/.config/hypr/bindings.conf ;;
  *Input*) open_in_editor ~/.config/hypr/input.conf ;;
  *Defaults*) show_setup_default_menu ;;
  *DNS*) present_terminal omarchy-qvos-setup-dns ;;
  *Security*) show_setup_security_menu ;;
  *Config*) show_setup_config_menu ;;
  *) show_settings_menu ;;
  esac
}

show_install_menu() {
  if [[ $INSTALL_EASY_LIST_ACTIVE == "true" ]]; then
    show_install_easy_list_menu
    return
  fi

  case $(menu "Install" "󰣇  Package\n󰣇  AUR\n󰏖  Easy List") in
  *Package*) terminal omarchy-pkg-install ;;
  *AUR*) terminal omarchy-pkg-aur-install ;;
  *Easy*) show_install_easy_list_menu ;;
  *) show_settings_menu ;;
  esac
}

show_install_easy_list_menu() {
  case $(menu "Easy List" "󰏖  qvCORE (Optional)\n  Web App\n  TUI\n  Service\n  Style\n󰵮  Development\n  Editor\n  Terminal\n  Browser\n󱚤  AI\n  Gaming\n󰍲  Windows") in
  *qvCORE*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_qvcore_menu show_install_menu
    ;;
  *Web*) present_terminal omarchy-webapp-install ;;
  *TUI*) present_terminal omarchy-tui-install ;;
  *Service*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_service_menu
    ;;
  *Style*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_style_menu
    ;;
  *Development*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_development_menu
    ;;
  *Editor*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_editor_menu
    ;;
  *Terminal*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_terminal_menu
    ;;
  *Browser*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_browser_menu
    ;;
  *AI*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_ai_menu
    ;;
  *Gaming*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_gaming_menu
    ;;
  *Windows*) launch_software_action windows ;;
  *)
    INSTALL_EASY_LIST_ACTIVE=false
    show_install_menu
    ;;
  esac
}

show_qvcore_menu() {
  local back_menu=${1:-show_settings_software_menu}
  local catalog="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/qv/core/catalog.tsv"
  local state_dir="$HOME/.local/state/qvos/qvcore"
  local component
  local label
  local icon
  local extra
  local action
  local choice
  local index
  local options=""
  local -a components=()
  local -a labels=()
  local -a actions=()

  while IFS=$'\t' read -r component label icon extra; do
    [[ -n $component && $component != "#"* ]] || continue
    [[ -n $label && -n $icon && -z ${extra:-} ]] || continue
    if [[ -f $state_dir/$component ]]; then
      action="Uninstall"
    else
      action="Install"
    fi
    components+=("$component")
    labels+=("$label")
    actions+=("$action")
    options="${options:+$options\n}$icon  $label — $action"
  done <"$catalog"

  choice=$(menu "qvCORE" "$options")
  choice=${choice#*  }
  choice=${choice% — *}

  for index in "${!labels[@]}"; do
    [[ $choice == "${labels[$index]}" ]] || continue
    launch_software_action "${components[$index]}"
    return
  done

  "$back_menu"
}

show_remove_menu() {
  case $(menu "Remove" "󰣇  Package\n  Web App\n  TUI\n󰵮  Development\n󰸌  Theme\n  Browser\n  Dictation\n  Gaming\n󰍲  Windows\n  Security") in
  *Package*) terminal omarchy-pkg-remove ;;
  *Web*) present_terminal omarchy-webapp-remove ;;
  *TUI*) present_terminal omarchy-tui-remove ;;
  *Development*) show_remove_development_menu ;;
  *Theme*) present_terminal omarchy-theme-remove ;;
  *Browser*) show_remove_browser_menu ;;
  *Dictation*) launch_software_action dictation ;;
  *Gaming*) show_remove_gaming_menu ;;
  *Windows*) launch_software_action windows ;;
  *Security*) show_remove_security_menu ;;
  *) show_settings_menu ;;
  esac
}

show_update_menu() {
  omarchy-launch-qvos-update
}

show_update_process_menu() {
  case $(menu "Restart" "  Hypridle\n  Hyprsunset\n󰎟  Mako\n  Swayosd\n󰌧  Walker\n󰍜  Waybar") in
  *Hypridle*) launch_tui_task restart-hypridle ;;
  *Hyprsunset*) launch_tui_task restart-hyprsunset ;;
  *Mako*) launch_tui_task restart-mako ;;
  *Swayosd*) launch_tui_task restart-swayosd ;;
  *Walker*) launch_tui_task restart-walker ;;
  *Waybar*) launch_tui_task restart-waybar ;;
  *) show_update_menu ;;
  esac
}

show_update_config_menu() {
  case $(menu "Use default config" "  Hyprland\n  Hypridle\n  Hyprlock\n  Hyprsunset\n󱣴  Plymouth\n  Swayosd\n  Tmux\n󰌧  Walker\n󰍜  Waybar") in
  *Hyprland*) present_terminal omarchy-refresh-hyprland ;;
  *Hypridle*) present_terminal omarchy-refresh-hypridle ;;
  *Hyprlock*) present_terminal omarchy-refresh-hyprlock ;;
  *Hyprsunset*) present_terminal omarchy-refresh-hyprsunset ;;
  *Plymouth*) present_terminal omarchy-refresh-plymouth ;;
  *Swayosd*) present_terminal omarchy-refresh-swayosd ;;
  *Tmux*) present_terminal omarchy-refresh-tmux ;;
  *Walker*) present_terminal omarchy-refresh-walker ;;
  *Waybar*) present_terminal omarchy-qvos-refresh-waybar ;;
  *) show_update_menu ;;
  esac
}

go_to_menu() {
  case "${1,,}" in
  concept:*) show_concept_menu "${1#concept:}" ;;
  software-development*) show_software_menu development ;;
  software-javascript*) show_software_menu javascript ;;
  software-browser*) show_software_menu browser ;;
  software-gaming*) show_software_menu gaming ;;
  software-qvcore*) show_software_menu qvcore ;;
  software*) show_software_menu ;;
  *apps*)
    set_qvos_menu_mode apps
    omarchy-launch-walker \
      --theme qvos-omarchy-menu \
      --set qvos-omarchy-menu \
      --width 560 \
      --minheight 1 \
      --maxheight 630 \
      --placeholder "Search…  ·  Tab: Apps ↔ Menu"
    ;;
  *settings*) show_settings_menu ;;
  *more*) show_more_menu ;;
  *learn*) show_learn_menu ;;
  *trigger*) show_trigger_menu ;;
  *toggle*) show_toggle_menu ;;
  *update-hardware*) show_update_hardware_menu ;;
  *hardware*) show_hardware_menu ;;
  *share*) show_share_menu ;;
  *reminder-set*) show_custom_reminder_input ;;
  *reminder*) show_reminder_menu ;;
  *background*) show_background_menu ;;
  *capture*) show_capture_menu ;;
  *install-style*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_style_menu
    ;;
  *install-font*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_font_menu
    ;;
  *style-about*) show_about_menu ;;
  *screensaver-style*) show_screensaver_menu ;;
  *style*) show_style_menu ;;
  *theme*) show_theme_menu ;;
  *font*) show_font_menu ;;
  *screenrecord*) show_screenrecord_menu ;;
  *setup-defaults*) show_setup_default_menu ;;
  *setup-config*) show_setup_config_menu ;;
  *setup-security*) show_setup_security_menu ;;
  *system-sleep*) show_setup_system_menu ;;
  *setup*) show_setup_menu ;;
  *power*) show_setup_power_menu ;;
  *qvcore*) show_qvcore_menu show_settings_software_menu ;;
  *install-easy*) show_install_easy_list_menu ;;
  *install-service*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_service_menu
    ;;
  *install-development*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_development_menu
    ;;
  *install-javascript*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_javascript_menu
    ;;
  *install-php*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_php_menu
    ;;
  *install-elixir*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_elixir_menu
    ;;
  *install-editor*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_editor_menu
    ;;
  *install-terminal*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_terminal_menu
    ;;
  *install-browser*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_browser_menu
    ;;
  *install-ai*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_ai_menu
    ;;
  *install-gaming*)
    INSTALL_EASY_LIST_ACTIVE=true
    show_install_gaming_menu
    ;;
  *install*) show_install_menu ;;
  *remove-development*) show_remove_development_menu ;;
  *remove-javascript*) show_remove_javascript_menu ;;
  *remove-php*) show_remove_php_menu ;;
  *remove-elixir*) show_remove_elixir_menu ;;
  *remove-browser*) show_remove_browser_menu ;;
  *remove-gaming*) show_remove_gaming_menu ;;
  *remove-security*) show_remove_security_menu ;;
  *remove*) show_remove_menu ;;
  *update-config*) show_update_config_menu ;;
  *update-process*) show_update_process_menu ;;
  *update-password*) show_update_password_menu ;;
  *update*) show_update_menu ;;
  *about*) show_about ;;
  *system*) show_system_menu ;;
  esac
}
