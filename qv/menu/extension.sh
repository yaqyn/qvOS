# shellcheck shell=bash

# qvOS menu overrides loaded before personal Omarchy menu extensions.

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

show_setup_menu() {
  case $(menu "Setup" "󰒓  System\n  Style\n  Terminal\n  Editor\n  Browser\n  Audio\n  Wi-Fi\n󰂯  Bluetooth\n  Timezone\n󰐕  DNS\n󱋆  Security\n󰍲  Windows\n  Services") in
  *System*) show_setup_system_menu ;;
  *Style*) show_style_menu ;;
  *Terminal*) show_setup_terminal_menu ;;
  *Editor*) show_setup_editor_menu ;;
  *Browser*) show_setup_browser_menu ;;
  *Audio*) show_setup_audio_menu ;;
  *Wi-Fi*) show_setup_wifi_menu ;;
  *Bluetooth*) show_setup_bluetooth_menu ;;
  *Timezone*) present_terminal omarchy-tz-select ;;
  *DNS*) present_terminal omarchy-qvos-setup-dns ;;
  *Security*) show_setup_security_menu ;;
  *Windows*) present_terminal "omarchy-windows-vm install" ;;
  *Services*) show_setup_services_menu ;;
  *) show_main_menu ;;
  esac
}

show_install_menu() {
  case $(menu "Install" "󰏖  qvCORE (Optional)\n󰣇  Package\n󰣇  AUR\n  Web App\n  TUI\n  Service\n  Style\n󰵮  Development\n  Editor\n  Terminal\n  Browser\n󱚤  AI\n  Gaming\n󰍲  Windows") in
  *qvCORE*) show_qvcore_menu show_install_menu ;;
  *Package*) terminal omarchy-pkg-install ;;
  *AUR*) terminal omarchy-pkg-aur-install ;;
  *Web*) present_terminal omarchy-webapp-install ;;
  *TUI*) present_terminal omarchy-tui-install ;;
  *Service*) show_install_service_menu ;;
  *Style*) show_install_style_menu ;;
  *Development*) show_install_development_menu ;;
  *Editor*) show_install_editor_menu ;;
  *Terminal*) show_install_terminal_menu ;;
  *Browser*) show_install_browser_menu ;;
  *AI*) show_install_ai_menu ;;
  *Gaming*) show_install_gaming_menu ;;
  *Windows*) present_terminal "omarchy-windows-vm install" ;;
  *) show_main_menu ;;
  esac
}

show_qvcore_menu() {
  local back_menu=${1:-show_install_menu}

  case $(menu "qvCORE — Optional Setups" "󰓅  Health / Repair\n󰐕  Disable Integrations\n  Install All Setups\n󰖟  Brave\n󰖂  WARP\n  Share\n󰵮  Devel\n󱚤  Codex\n󰌾  Proton\n  Steam\n󰕧  Media") in
  *Health*) present_terminal omarchy-qvcore-repair ;;
  *Disable*) present_terminal omarchy-qvcore-disable ;;
  *"Install All Setups"*) present_terminal omarchy-install-qvcore ;;
  *Brave*) present_terminal "omarchy-install-qvcore brave-origin" ;;
  *WARP*) present_terminal "omarchy-install-qvcore warp" ;;
  *Share*) present_terminal "omarchy-install-qvcore share" ;;
  *Devel*) present_terminal "omarchy-install-qvcore dev" ;;
  *Codex*) present_terminal "omarchy-install-qvcore codex" ;;
  *Proton*) present_terminal "omarchy-install-qvcore proton" ;;
  *Steam*) present_terminal "omarchy-install-qvcore steam" ;;
  *Media*) present_terminal "omarchy-install-qvcore media" ;;
  *) "$back_menu" ;;
  esac
}

show_qvos_menu() {
  case $(menu "qvOS" "󱅾  Update qvOS\n󰑓  Repair qvOS\n󰘶  Personal Software\n󰓅  qvCORE Health / Repair\n󰐕  Disable qvCORE Integrations\n󰏖  qvCORE (Optional)" "--width 360 --maxheight 760") in
  *"Update qvOS"*) present_terminal omarchy-qvos-update ;;
  *"Repair qvOS"*) present_terminal omarchy-qvos-repair ;;
  *"Personal Software"*) present_terminal "omarchy-qvos-personal-software --remove" ;;
  *Health*) present_terminal omarchy-qvcore-repair ;;
  *Disable*) present_terminal omarchy-qvcore-disable ;;
  *qvCORE*) show_qvcore_menu show_qvos_menu ;;
  *) back_to show_main_menu ;;
  esac
}

show_remove_menu() {
  case $(menu "Remove" "󰣇  Package\n󰘶  Personal Software\n  Web App\n  TUI\n󰵮  Development\n󰸌  Theme\n  Browser\n  Dictation\n  Gaming\n󰍲  Windows\n  Security") in
  *Package*) terminal omarchy-pkg-remove ;;
  *"Personal Software"*) present_terminal "omarchy-qvos-personal-software --remove" ;;
  *Web*) present_terminal omarchy-webapp-remove ;;
  *TUI*) present_terminal omarchy-tui-remove ;;
  *Development*) show_remove_development_menu ;;
  *Theme*) present_terminal omarchy-theme-remove ;;
  *Browser*) show_remove_browser_menu ;;
  *Dictation*) present_terminal omarchy-voxtype-remove ;;
  *Gaming*) show_remove_gaming_menu ;;
  *Windows*) present_terminal "omarchy-windows-vm remove" ;;
  *Security*) show_remove_security_menu ;;
  *) show_main_menu ;;
  esac
}

show_update_menu() {
  case $(menu "Update" "󱅾  qvOS\n󰑓  Repair qvOS\n  Config\n󰸌  Extra Themes\n  Process\n󰇅  Hardware\n  Firmware\n  Password\n  Timezone\n  Time") in
  *Repair*) present_terminal omarchy-qvos-repair ;;
  *qvOS*) present_terminal omarchy-qvos-update ;;
  *Config*) show_update_config_menu ;;
  *Themes*) present_terminal omarchy-theme-update ;;
  *Process*) show_update_process_menu ;;
  *Hardware*) show_update_hardware_menu ;;
  *Firmware*) present_terminal omarchy-update-firmware ;;
  *Timezone*) present_terminal omarchy-tz-select ;;
  *Time*) present_terminal omarchy-update-time ;;
  *Password*) show_update_password_menu ;;
  *) show_main_menu ;;
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
  *apps*) walker -p "Launch…" ;;
  *learn*) show_learn_menu ;;
  *trigger*) show_trigger_menu ;;
  *toggle*) show_toggle_menu ;;
  *hardware*) show_hardware_menu ;;
  *share*) show_share_menu ;;
  *reminder-set*) show_custom_reminder_input ;;
  *reminder*) show_reminder_menu ;;
  *background*) show_background_menu ;;
  *capture*) show_capture_menu ;;
  *style*) show_style_menu ;;
  *theme*) show_theme_menu ;;
  *screenrecord*) show_screenrecord_menu ;;
  *setup*) show_setup_menu ;;
  *power*) show_setup_power_menu ;;
  *qvos*) show_qvos_menu ;;
  *qvcore*) show_qvcore_menu show_install_menu ;;
  *install*) show_install_menu ;;
  *remove*) show_remove_menu ;;
  *update*) show_update_menu ;;
  *about*) show_about ;;
  *system*) show_system_menu ;;
  esac
}
