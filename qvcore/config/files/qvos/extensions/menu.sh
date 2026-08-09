# Override qvOS menu functions with personal submenus.
# qvOS loads this personal file after qvcore/menu/{base,routes}.
#
# WARNING: Overridden functions will not receive later qvOS menu changes.
#
# Example of minimal system menu:
#
# show_system_menu() {
#   case $(menu "System" "  Lock\n󰌥  Shutdown") in
#   *Lock*) qv-system-lock ;;
#   *Shutdown*) qv-system-shutdown ;;
#   *) back_to show_main_menu ;;
#   esac
# }
#
# Example of overriding just the about menu action: (Using zsh instead of bash (default))
#
# show_about() {
#   exec qv-launch-or-focus-tui "zsh -c 'fastfetch; read -k 1'"
# }
