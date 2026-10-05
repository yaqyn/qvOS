-- qvOS keybindings.
--
-- Ownership:
-- - This is the complete active binding source; no inherited binding layer exists.
-- - Keep every modifier and key pair unique unless press/release semantics require both.
--
-- Letter families:
-- - Family One uses SUPER with optional SHIFT and CTRL.
-- - Family Two adds ALT with optional SHIFT and CTRL.
-- - Ease descends through SUPER, SHIFT, CTRL, SHIFT+CTRL, ALT, CTRL+ALT,
--   SHIFT+ALT, and SHIFT+CTRL+ALT.
-- - CTRL modifies the action beside it; SHIFT introduces the next major action.

-- Family index:
-- - A: development; B/Z: browsers; E: files and editor.
-- - F/S: window states and special workspace; R: reminders.
-- - W: system controls.
-- - X/Return: terminal and tmux.

-- Letter bindings: applications and controls.

-- X and Return: terminal and tmux.

-- X family.
qv.bind({ keys = [[SUPER + X]], description = [[Default terminal]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec]] })
qv.bind({ keys = [[SUPER + SHIFT + X]], description = [[Tmux]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/lib/qvos/tmux/qvos-tmux last]] })
qv.bind({ keys = [[SUPER + CTRL + X]], description = [[Default terminal here]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here terminal]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + X]], description = [[Tmux manager]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/lib/qvos/tmux/qvos-tmux manager]] })

-- Return family mirrors X.
qv.bind({ keys = [[SUPER + RETURN]], description = [[Default terminal]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec]] })
qv.bind({ keys = [[SUPER + SHIFT + RETURN]], description = [[Tmux]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/lib/qvos/tmux/qvos-tmux last]] })
qv.bind({ keys = [[SUPER + CTRL + RETURN]], description = [[Default terminal here]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here terminal]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + RETURN]], description = [[Tmux manager]], dispatcher = [[exec]], argument = [[qv-launch-app -- xdg-terminal-exec --app-id=org.qvos.tmux-manager --title="qvOS tmux" ~/.local/lib/qvos/tmux/qvos-tmux manager]] })

-- A: development.
qv.bind({ keys = [[SUPER + SHIFT + A]], description = [[Codex YOLO]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here codex-yolo "$HOME"]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + A]], description = [[Codex YOLO here]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/context/qvos-launch-terminal-here codex-yolo]] })

-- SUPER+C remains Universal copy.

-- R: reminders.
qv.bind({ keys = [[SUPER + ALT + R]], description = [[Set reminder]], dispatcher = [[exec]], argument = [[qv-menu reminder-set]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + R]], description = [[Clear reminders]], dispatcher = [[exec]], argument = [[qv-reminder clear]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + R]], description = [[Show reminders]], dispatcher = [[exec]], argument = [[qv-reminder show]] })

-- W: window and system controls.
-- SUPER+W closes the active window; SUPER+CTRL+W opens Wi-Fi controls.
qv.bind({ keys = [[SUPER + SHIFT + W]], description = [[Audio controls]], dispatcher = [[exec]], argument = [[qv-launch-audio]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + W]], description = [[Bluetooth controls]], dispatcher = [[exec]], argument = [[qv-launch-bluetooth]] })

-- F/S: window states and special workspace.
-- SUPER+F is full screen and SUPER+S is the special workspace.
qv.bind({ keys = [[SUPER + SHIFT + F]], description = [[Tiled full screen]], dispatcher = [[fullscreenstate]], argument = [[0 2]] })
qv.bind({ keys = [[SUPER + CTRL + F]], description = [[Toggle window floating/tiling]], dispatcher = [[togglefloating]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + F]], description = [[Pop window out (float & pin)]], dispatcher = [[exec]], argument = [[qv-hyprland-window-pop]] })
qv.bind({ keys = [[SUPER + CTRL + S]], description = [[Move window in or out of special workspace]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/hyprland/qvos-toggle-special-window]] })

-- E: files and editor.
qv.bind({ keys = [[SUPER + E]], description = [[Thunar]], dispatcher = [[exec]], argument = [[qv-launch-app -- ~/.local/lib/qvos/thunar/launch "$HOME"]] })
qv.bind({ keys = [[SUPER + SHIFT + E]], description = [[Default editor]], dispatcher = [[exec]], argument = [[qv-launch-editor]] })
qv.bind({ keys = [[SUPER + CTRL + E]], description = [[Thunar here]], dispatcher = [[exec]], argument = [[qv-launch-app -- ~/.local/lib/qvos/thunar/launch "$(~/.local/lib/qvos/desktop/context/qvos-active-location)"]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + E]], description = [[Default editor here]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/context/qvos-launch-editor-here]] })
qv.bind({ keys = [[SUPER + ALT + E]], description = [[Obsidian]], dispatcher = [[exec]], argument = [[qv-launch-app -- obsidian]] })

-- B: browser.
qv.bind({ keys = [[SUPER + B]], description = [[Default browser]], dispatcher = [[exec]], argument = [[qv-launch-browser]] })
qv.bind({ keys = [[SUPER + CTRL + B]], description = [[Private default browser]], dispatcher = [[exec]], argument = [[qv-launch-browser --private]] })

-- Z: browsers, websites, localhost, and zoom.
qv.bind({ keys = [[SUPER + Z]], description = [[Default browser]], dispatcher = [[exec]], argument = [[qv-launch-browser]] })
qv.bind({ keys = [[SUPER + SHIFT + Z]], description = [[Dev browser (Chromium)]], dispatcher = [[exec]], argument = [[qv-launch-app -- chromium]] })
qv.bind({ keys = [[SUPER + CTRL + Z]], description = [[Private default browser]], dispatcher = [[exec]], argument = [[qv-launch-browser --private]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + Z]], description = [[Localhost]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/web/qvos-localhost-open]] })
qv.bind({ keys = [[SUPER + ALT + Z]], description = [[Zoom in]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/hyprland/qvos-runtime-config config cursor zoom_factor "$(hyprctl getoption cursor:zoom_factor -j | jq -r '.float + 1')"]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + Z]], description = [[Reset zoom]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/hyprland/qvos-runtime-config config cursor zoom_factor 1]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + Z]], description = [[Open website]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/web/qvos-website-open]] })

-- Alt letter family: window focus, placement, and sizing.

-- ALT+WASD: move focus.
qv.bind({ keys = [[SUPER + ALT + A]], description = [[Focus left]], dispatcher = [[movefocus]], argument = [[l]] })
qv.bind({ keys = [[SUPER + ALT + W]], description = [[Focus up]], dispatcher = [[movefocus]], argument = [[u]] })
qv.bind({ keys = [[SUPER + ALT + D]], description = [[Focus right]], dispatcher = [[movefocus]], argument = [[r]] })
qv.bind({ keys = [[SUPER + ALT + S]], description = [[Focus down]], dispatcher = [[movefocus]], argument = [[d]] })

-- CTRL+ALT+WASD: resize windows.
qv.bind({ keys = [[SUPER + CTRL + ALT + A]], description = [[Resize window left]], dispatcher = [[resizeactive]], argument = [[-100 0]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + W]], description = [[Resize window up]], dispatcher = [[resizeactive]], argument = [[0 -100]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + D]], description = [[Resize window right]], dispatcher = [[resizeactive]], argument = [[100 0]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + S]], description = [[Resize window down]], dispatcher = [[resizeactive]], argument = [[0 100]] })

-- SHIFT+ALT+WASD: swap windows.
qv.bind({ keys = [[SUPER + SHIFT + ALT + A]], description = [[Swap window left]], dispatcher = [[swapwindow]], argument = [[l]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + W]], description = [[Swap window up]], dispatcher = [[swapwindow]], argument = [[u]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + D]], description = [[Swap window right]], dispatcher = [[swapwindow]], argument = [[r]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + S]], description = [[Swap window down]], dispatcher = [[swapwindow]], argument = [[d]] })

-- SHIFT+CTRL+ALT+WASD: move the workspace between monitors.
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + A]], description = [[Move workspace to left monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[l]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + W]], description = [[Move workspace to up monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[u]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + D]], description = [[Move workspace to right monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[r]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + ALT + S]], description = [[Move workspace to down monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[d]] })

-- Arrow family: the same spatial actions without ALT.

-- CTRL+ARROWS: resize windows.
qv.bind({ keys = [[SUPER + CTRL + LEFT]], description = [[Resize window left]], dispatcher = [[resizeactive]], argument = [[-100 0]] })
qv.bind({ keys = [[SUPER + CTRL + UP]], description = [[Resize window up]], dispatcher = [[resizeactive]], argument = [[0 -100]] })
qv.bind({ keys = [[SUPER + CTRL + RIGHT]], description = [[Resize window right]], dispatcher = [[resizeactive]], argument = [[100 0]] })
qv.bind({ keys = [[SUPER + CTRL + DOWN]], description = [[Resize window down]], dispatcher = [[resizeactive]], argument = [[0 100]] })

-- SHIFT+CTRL+ARROWS: move the workspace between monitors.
qv.bind({ keys = [[SUPER + SHIFT + CTRL + LEFT]], description = [[Move workspace to left monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[l]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + UP]], description = [[Move workspace to up monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[u]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + RIGHT]], description = [[Move workspace to right monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[r]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + DOWN]], description = [[Move workspace to down monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[d]] })

-- Non-letter controls.

-- Shared qvOS menu, opened on Apps.
qv.bind({ keys = [[SUPER + SPACE]], description = [[qvOS apps]], dispatcher = [[exec]], argument = [[qv-menu apps]] })

-- Capture.
qv.bind({ keys = [[SUPER + SHIFT + PRINT]], description = [[Capture menu]], dispatcher = [[exec]], argument = [[qv-menu capture]] })

-- Gaming workspace.
qv.bind({ keys = [[SUPER + grave]], description = [[Gaming workspace]], dispatcher = [[workspace]], argument = [[name:G]] })
qv.bind({ keys = [[SUPER + SHIFT + grave]], description = [[Move window to gaming workspace]], dispatcher = [[movetoworkspace]], argument = [[name:G]] })
qv.bind({ keys = [[SUPER + CTRL + grave]], description = [[Steam]], dispatcher = [[exec]], argument = [[setsid gtk-launch steam >/dev/null 2>&1]] })

-- Window and workspace controls.

-- Window lifecycle and layout.
qv.bind({ keys = [[SUPER + W]], description = [[Close window]], dispatcher = [[killactive]] })
qv.bind({ keys = [[CTRL + ALT + DELETE]], description = [[Close all windows]], dispatcher = [[exec]], argument = [[qv-hyprland-window-close-all]] })
qv.bind({ keys = [[SUPER + J]], description = [[Toggle window split]], dispatcher = [[layoutmsg]], argument = [[togglesplit]] })
qv.bind({ keys = [[SUPER + P]], description = [[Pseudo window]], dispatcher = [[pseudo]] })
qv.bind({ keys = [[SUPER + F]], description = [[Full screen]], dispatcher = [[fullscreen]], argument = [[0]] })
qv.bind({ keys = [[SUPER + ALT + F]], description = [[Full width]], dispatcher = [[fullscreen]], argument = [[1]] })
qv.bind({ keys = [[SUPER + L]], description = [[Toggle workspace layout]], dispatcher = [[exec]], argument = [[qv-hyprland-workspace-layout-toggle]] })

-- Focus with SUPER + arrow keys.
qv.bind({ keys = [[SUPER + LEFT]], description = [[Focus on left window]], dispatcher = [[movefocus]], argument = [[l]] })
qv.bind({ keys = [[SUPER + RIGHT]], description = [[Focus on right window]], dispatcher = [[movefocus]], argument = [[r]] })
qv.bind({ keys = [[SUPER + UP]], description = [[Focus on above window]], dispatcher = [[movefocus]], argument = [[u]] })
qv.bind({ keys = [[SUPER + DOWN]], description = [[Focus on below window]], dispatcher = [[movefocus]], argument = [[d]] })

-- Switch workspaces with SUPER + [1-9; 0].
qv.bind({ keys = [[SUPER + code:10]], description = [[Switch to workspace 1]], dispatcher = [[workspace]], argument = [[1]] })
qv.bind({ keys = [[SUPER + code:11]], description = [[Switch to workspace 2]], dispatcher = [[workspace]], argument = [[2]] })
qv.bind({ keys = [[SUPER + code:12]], description = [[Switch to workspace 3]], dispatcher = [[workspace]], argument = [[3]] })
qv.bind({ keys = [[SUPER + code:13]], description = [[Switch to workspace 4]], dispatcher = [[workspace]], argument = [[4]] })
qv.bind({ keys = [[SUPER + code:14]], description = [[Switch to workspace 5]], dispatcher = [[workspace]], argument = [[5]] })
qv.bind({ keys = [[SUPER + code:15]], description = [[Switch to workspace 6]], dispatcher = [[workspace]], argument = [[6]] })
qv.bind({ keys = [[SUPER + code:16]], description = [[Switch to workspace 7]], dispatcher = [[workspace]], argument = [[7]] })
qv.bind({ keys = [[SUPER + code:17]], description = [[Switch to workspace 8]], dispatcher = [[workspace]], argument = [[8]] })
qv.bind({ keys = [[SUPER + code:18]], description = [[Switch to workspace 9]], dispatcher = [[workspace]], argument = [[9]] })
qv.bind({ keys = [[SUPER + code:19]], description = [[Switch to workspace 10]], dispatcher = [[workspace]], argument = [[10]] })

-- Move the active window with SUPER + SHIFT + [1-9; 0].
qv.bind({ keys = [[SUPER + SHIFT + code:10]], description = [[Move window to workspace 1]], dispatcher = [[movetoworkspace]], argument = [[1]] })
qv.bind({ keys = [[SUPER + SHIFT + code:11]], description = [[Move window to workspace 2]], dispatcher = [[movetoworkspace]], argument = [[2]] })
qv.bind({ keys = [[SUPER + SHIFT + code:12]], description = [[Move window to workspace 3]], dispatcher = [[movetoworkspace]], argument = [[3]] })
qv.bind({ keys = [[SUPER + SHIFT + code:13]], description = [[Move window to workspace 4]], dispatcher = [[movetoworkspace]], argument = [[4]] })
qv.bind({ keys = [[SUPER + SHIFT + code:14]], description = [[Move window to workspace 5]], dispatcher = [[movetoworkspace]], argument = [[5]] })
qv.bind({ keys = [[SUPER + SHIFT + code:15]], description = [[Move window to workspace 6]], dispatcher = [[movetoworkspace]], argument = [[6]] })
qv.bind({ keys = [[SUPER + SHIFT + code:16]], description = [[Move window to workspace 7]], dispatcher = [[movetoworkspace]], argument = [[7]] })
qv.bind({ keys = [[SUPER + SHIFT + code:17]], description = [[Move window to workspace 8]], dispatcher = [[movetoworkspace]], argument = [[8]] })
qv.bind({ keys = [[SUPER + SHIFT + code:18]], description = [[Move window to workspace 9]], dispatcher = [[movetoworkspace]], argument = [[9]] })
qv.bind({ keys = [[SUPER + SHIFT + code:19]], description = [[Move window to workspace 10]], dispatcher = [[movetoworkspace]], argument = [[10]] })

-- Move the active window silently with SUPER + SHIFT + ALT + [1-9; 0].
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:10]], description = [[Move window silently to workspace 1]], dispatcher = [[movetoworkspacesilent]], argument = [[1]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:11]], description = [[Move window silently to workspace 2]], dispatcher = [[movetoworkspacesilent]], argument = [[2]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:12]], description = [[Move window silently to workspace 3]], dispatcher = [[movetoworkspacesilent]], argument = [[3]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:13]], description = [[Move window silently to workspace 4]], dispatcher = [[movetoworkspacesilent]], argument = [[4]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:14]], description = [[Move window silently to workspace 5]], dispatcher = [[movetoworkspacesilent]], argument = [[5]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:15]], description = [[Move window silently to workspace 6]], dispatcher = [[movetoworkspacesilent]], argument = [[6]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:16]], description = [[Move window silently to workspace 7]], dispatcher = [[movetoworkspacesilent]], argument = [[7]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:17]], description = [[Move window silently to workspace 8]], dispatcher = [[movetoworkspacesilent]], argument = [[8]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:18]], description = [[Move window silently to workspace 9]], dispatcher = [[movetoworkspacesilent]], argument = [[9]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + code:19]], description = [[Move window silently to workspace 10]], dispatcher = [[movetoworkspacesilent]], argument = [[10]] })

-- Special workspace and workspace history.
qv.bind({ keys = [[SUPER + S]], description = [[Toggle scratchpad]], dispatcher = [[togglespecialworkspace]], argument = [[scratchpad]] })
qv.bind({ keys = [[SUPER + TAB]], description = [[Next workspace]], dispatcher = [[workspace]], argument = [[e+1]] })
qv.bind({ keys = [[SUPER + SHIFT + TAB]], description = [[Previous workspace]], dispatcher = [[workspace]], argument = [[e-1]] })
qv.bind({ keys = [[SUPER + CTRL + TAB]], description = [[Former workspace]], dispatcher = [[workspace]], argument = [[previous]] })

-- Move workspaces between monitors.
qv.bind({ keys = [[SUPER + SHIFT + ALT + LEFT]], description = [[Move workspace to left monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[l]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + RIGHT]], description = [[Move workspace to right monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[r]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + UP]], description = [[Move workspace to up monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[u]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + DOWN]], description = [[Move workspace to down monitor]], dispatcher = [[movecurrentworkspacetomonitor]], argument = [[d]] })

-- Swap adjacent windows.
qv.bind({ keys = [[SUPER + SHIFT + LEFT]], description = [[Swap window to the left]], dispatcher = [[swapwindow]], argument = [[l]] })
qv.bind({ keys = [[SUPER + SHIFT + RIGHT]], description = [[Swap window to the right]], dispatcher = [[swapwindow]], argument = [[r]] })
qv.bind({ keys = [[SUPER + SHIFT + UP]], description = [[Swap window up]], dispatcher = [[swapwindow]], argument = [[u]] })
qv.bind({ keys = [[SUPER + SHIFT + DOWN]], description = [[Swap window down]], dispatcher = [[swapwindow]], argument = [[d]] })

-- Cycle windows and monitors.
qv.bind({ keys = [[ALT + TAB]], description = [[Focus on next window]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/hyprland/qvos-runtime-config window cycle next]] })
qv.bind({ keys = [[ALT + SHIFT + TAB]], description = [[Focus on previous window]], dispatcher = [[exec]], argument = [[~/.local/lib/qvos/desktop/hyprland/qvos-runtime-config window cycle previous]] })
qv.bind({ keys = [[CTRL + ALT + TAB]], description = [[Focus on next monitor]], dispatcher = [[focusmonitor]], argument = [[+1]] })
qv.bind({ keys = [[CTRL + ALT + SHIFT + TAB]], description = [[Focus on previous monitor]], dispatcher = [[focusmonitor]], argument = [[-1]] })

-- Directional size adjustments.
qv.bind({ keys = [[SUPER + code:20]], description = [[Expand window left]], dispatcher = [[resizeactive]], argument = [[-100 0]] }) -- - key
qv.bind({ keys = [[SUPER + code:21]], description = [[Shrink window left]], dispatcher = [[resizeactive]], argument = [[100 0]] }) -- = key
qv.bind({ keys = [[SUPER + SHIFT + code:20]], description = [[Shrink window up]], dispatcher = [[resizeactive]], argument = [[0 -100]] })
qv.bind({ keys = [[SUPER + SHIFT + code:21]], description = [[Expand window down]], dispatcher = [[resizeactive]], argument = [[0 100]] })

-- Mouse window and workspace control.
qv.bind({ keys = [[SUPER + mouse_down]], description = [[Scroll active workspace forward]], dispatcher = [[workspace]], argument = [[e+1]] })
qv.bind({ keys = [[SUPER + mouse_up]], description = [[Scroll active workspace backward]], dispatcher = [[workspace]], argument = [[e-1]] })
qv.bind({ keys = [[SUPER + mouse:272]], description = [[Move window]], dispatcher = [[movewindow]] })
qv.bind({ keys = [[SUPER + mouse:273]], description = [[Resize window]], dispatcher = [[resizewindow]] })

-- Window groups.
qv.bind({ keys = [[SUPER + G]], description = [[Toggle window grouping]], dispatcher = [[togglegroup]] })
qv.bind({ keys = [[SUPER + ALT + G]], description = [[Move active window out of group]], dispatcher = [[moveoutofgroup]] })
qv.bind({ keys = [[SUPER + ALT + LEFT]], description = [[Move window to group on left]], dispatcher = [[moveintogroup]], argument = [[l]] })
qv.bind({ keys = [[SUPER + ALT + RIGHT]], description = [[Move window to group on right]], dispatcher = [[moveintogroup]], argument = [[r]] })
qv.bind({ keys = [[SUPER + ALT + UP]], description = [[Move window to group on top]], dispatcher = [[moveintogroup]], argument = [[u]] })
qv.bind({ keys = [[SUPER + ALT + DOWN]], description = [[Move window to group on bottom]], dispatcher = [[moveintogroup]], argument = [[d]] })
qv.bind({ keys = [[SUPER + ALT + TAB]], description = [[Next window in group]], dispatcher = [[changegroupactive]], argument = [[f]] })
qv.bind({ keys = [[SUPER + ALT + SHIFT + TAB]], description = [[Previous window in group]], dispatcher = [[changegroupactive]], argument = [[b]] })
qv.bind({ keys = [[SUPER + ALT + mouse_down]], description = [[Next window in group]], dispatcher = [[changegroupactive]], argument = [[f]] })
qv.bind({ keys = [[SUPER + ALT + mouse_up]], description = [[Previous window in group]], dispatcher = [[changegroupactive]], argument = [[b]] })
qv.bind({ keys = [[SUPER + ALT + code:10]], description = [[Switch to group window 1]], dispatcher = [[changegroupactive]], argument = [[1]] })
qv.bind({ keys = [[SUPER + ALT + code:11]], description = [[Switch to group window 2]], dispatcher = [[changegroupactive]], argument = [[2]] })
qv.bind({ keys = [[SUPER + ALT + code:12]], description = [[Switch to group window 3]], dispatcher = [[changegroupactive]], argument = [[3]] })
qv.bind({ keys = [[SUPER + ALT + code:13]], description = [[Switch to group window 4]], dispatcher = [[changegroupactive]], argument = [[4]] })
qv.bind({ keys = [[SUPER + ALT + code:14]], description = [[Switch to group window 5]], dispatcher = [[changegroupactive]], argument = [[5]] })

-- Monitor scaling.
qv.bind({ keys = [[SUPER + code:61]], description = [[Cycle monitor scaling]], dispatcher = [[exec]], argument = [[qv-hyprland-monitor-scaling-cycle]] })
qv.bind({ keys = [[SUPER + ALT + code:61]], description = [[Cycle monitor scaling backwards]], dispatcher = [[exec]], argument = [[qv-hyprland-monitor-scaling-cycle --reverse]] })

-- Clipboard.
qv.bind({ keys = [[SUPER + C]], description = [[Universal copy]], dispatcher = [[sendshortcut]], argument = [[CTRL, Insert, activewindow]] })
qv.bind({ keys = [[SUPER + V]], description = [[Universal paste]], dispatcher = [[sendshortcut]], argument = [[SHIFT, Insert, activewindow]] })
qv.bind({ keys = [[SUPER + CTRL + V]], description = [[Clipboard manager]], dispatcher = [[exec]], argument = [[qv-launch-walker -m clipboard]] })

-- Menus and hardware keys.
qv.bind({ keys = [[SUPER + CTRL + O]], description = [[Toggle menu]], dispatcher = [[exec]], argument = [[qv-menu toggle]] })
qv.bind({ keys = [[SUPER + CTRL + H]], description = [[Hardware menu]], dispatcher = [[exec]], argument = [[qv-menu hardware]] })
qv.bind({ keys = [[SUPER + ALT + SPACE]], description = [[qvOS menu]], dispatcher = [[exec]], argument = [[qv-menu]] })
qv.bind({ keys = [[SUPER + SHIFT + code:201]], description = [[qvOS menu]], dispatcher = [[exec]], argument = [[qv-menu]] })
qv.bind({ keys = [[SUPER + ESCAPE]], description = [[System menu]], dispatcher = [[exec]], argument = [[qv-menu system]] })
qv.bind({ keys = [[XF86PowerOff]], description = [[Power menu]], dispatcher = [[exec]], argument = [[qv-menu system]], locked = true })
qv.bind({ keys = [[SUPER + K]], description = [[Show key bindings]], dispatcher = [[exec]], argument = [[qv-menu-keybindings]] })
qv.bind({ keys = [[XF86Calculator]], description = [[Calculator]], dispatcher = [[exec]], argument = [[gnome-calculator]] })

-- Appearance.
qv.bind({ keys = [[SUPER + SHIFT + SPACE]], description = [[Toggle top bar]], dispatcher = [[exec]], argument = [[qv-toggle-waybar]] })
qv.bind({ keys = [[SUPER + CTRL + SPACE]], description = [[Theme background menu]], dispatcher = [[exec]], argument = [[qv-menu background]] })
qv.bind({ keys = [[SUPER + SHIFT + CTRL + SPACE]], description = [[Theme menu]], dispatcher = [[exec]], argument = [[qv-menu theme]] })
qv.bind({ keys = [[SUPER + BACKSPACE]], description = [[Toggle window transparency]], dispatcher = [[exec]], argument = [[qv-hyprland-window-transparency-toggle]] })
qv.bind({ keys = [[SUPER + SHIFT + BACKSPACE]], description = [[Toggle window gaps]], dispatcher = [[exec]], argument = [[qv-hyprland-window-gaps-toggle]] })
qv.bind({ keys = [[SUPER + CTRL + BACKSPACE]], description = [[Toggle single-window square aspect]], dispatcher = [[exec]], argument = [[qv-hyprland-window-single-square-aspect-toggle]] })

-- Notifications.
qv.bind({ keys = [[SUPER + COMMA]], description = [[Dismiss last notification]], dispatcher = [[exec]], argument = [[makoctl dismiss]] })
qv.bind({ keys = [[SUPER + SHIFT + COMMA]], description = [[Dismiss all notifications]], dispatcher = [[exec]], argument = [[makoctl dismiss --all]] })
qv.bind({ keys = [[SUPER + CTRL + COMMA]], description = [[Toggle silencing notifications]], dispatcher = [[exec]], argument = [[qv-toggle-notification-silencing]] })
qv.bind({ keys = [[SUPER + ALT + COMMA]], description = [[Invoke last notification]], dispatcher = [[exec]], argument = [[makoctl invoke]] })
qv.bind({ keys = [[SUPER + SHIFT + ALT + COMMA]], description = [[Restore last notification]], dispatcher = [[exec]], argument = [[makoctl restore]] })

-- System toggles.
qv.bind({ keys = [[SUPER + CTRL + I]], description = [[Toggle locking on idle]], dispatcher = [[exec]], argument = [[qv-toggle-idle]] })
qv.bind({ keys = [[SUPER + CTRL + N]], description = [[Toggle nightlight]], dispatcher = [[exec]], argument = [[qv-toggle-nightlight]] })
qv.bind({ keys = [[SUPER + CTRL + Delete]], description = [[Toggle laptop display]], dispatcher = [[exec]], argument = [[qv-hyprland-monitor-internal toggle]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + Delete]], description = [[Toggle laptop display mirroring]], dispatcher = [[exec]], argument = [[qv-hyprland-monitor-internal-mirror toggle]] })
qv.bind({ keys = [[switch:on:Lid Switch]], dispatcher = [[exec]], argument = [[qv-hw-external-monitors && qv-hyprland-monitor-internal off]], locked = true })
qv.bind({ keys = [[switch:off:Lid Switch]], dispatcher = [[exec]], argument = [[qv-hyprland-monitor-internal on]], locked = true })

-- Capture and conversion.
qv.bind({ keys = [[PRINT]], description = [[Screenshot]], dispatcher = [[exec]], argument = [[qv-capture-screenshot]] })
qv.bind({ keys = [[ALT + PRINT]], description = [[Screenrecording]], dispatcher = [[exec]], argument = [[qv-menu screenrecord]] })
qv.bind({ keys = [[SUPER + PRINT]], description = [[Color picker]], dispatcher = [[exec]], argument = [[qv-capture-color]] })
qv.bind({ keys = [[SUPER + CTRL + PRINT]], description = [[Extract text (OCR) from screenshot]], dispatcher = [[exec]], argument = [[qv-capture-text-extraction]] })
qv.bind({ keys = [[SUPER + CTRL + PERIOD]], description = [[Transcode]], dispatcher = [[exec]], argument = [[qv-transcode]] })

-- Information and control panels.
qv.bind({ keys = [[SUPER + CTRL + ALT + T]], description = [[Show time]], dispatcher = [[exec]], argument = [[notify-send -u low "    $(date +"%A %H:%M  ·  %d %B %Y  ·  Week %V")"]] })
qv.bind({ keys = [[SUPER + CTRL + ALT + B]], description = [[Show battery remaining]], dispatcher = [[exec]], argument = [[notify-send -u low "$(qv-battery-status)"]] })
qv.bind({ keys = [[SUPER + CTRL + W]], description = [[Wifi controls]], dispatcher = [[exec]], argument = [[qv-launch-wifi]] })
qv.bind({ keys = [[SUPER + CTRL + T]], description = [[Activity]], dispatcher = [[exec]], argument = [[qv-launch-tui btop]] })

-- Dictation push-to-talk.
qv.bind({ keys = [[F9]], description = [[Start dictation (push-to-talk)]], dispatcher = [[exec]], argument = [[voxtype record start]] })
qv.bind({ keys = [[F9]], description = [[Stop dictation (push-to-talk)]], dispatcher = [[exec]], argument = [[voxtype record stop]], release = true })

-- Lock system.
qv.bind({ keys = [[SUPER + CTRL + L]], description = [[Lock system]], dispatcher = [[exec]], argument = [[qv-system-lock]] })

-- Media and laptop hardware.
qv.bind({ keys = [[XF86AudioRaiseVolume]], description = [[Volume up]], dispatcher = [[exec]], argument = [[qv-swayosd-client --output-volume raise]], repeating = true, locked = true })
qv.bind({ keys = [[XF86AudioLowerVolume]], description = [[Volume down]], dispatcher = [[exec]], argument = [[qv-swayosd-client --output-volume lower]], repeating = true, locked = true })
qv.bind({ keys = [[XF86AudioMute]], description = [[Mute]], dispatcher = [[exec]], argument = [[qv-swayosd-client --output-volume mute-toggle]], repeating = true, locked = true })
qv.bind({ keys = [[XF86AudioMicMute]], description = [[Mute microphone]], dispatcher = [[exec]], argument = [[qv-audio-input-mute]], repeating = true, locked = true })
qv.bind({ keys = [[XF86MonBrightnessUp]], description = [[Brightness up]], dispatcher = [[exec]], argument = [[qv-brightness-display +5%]], repeating = true, locked = true })
qv.bind({ keys = [[XF86MonBrightnessDown]], description = [[Brightness down]], dispatcher = [[exec]], argument = [[qv-brightness-display 5%-]], repeating = true, locked = true })
qv.bind({ keys = [[SHIFT + XF86MonBrightnessUp]], description = [[Brightness maximum]], dispatcher = [[exec]], argument = [[qv-brightness-display 100%]], repeating = true, locked = true })
qv.bind({ keys = [[SHIFT + XF86MonBrightnessDown]], description = [[Brightness minimum]], dispatcher = [[exec]], argument = [[qv-brightness-display 1%]], repeating = true, locked = true })
qv.bind({ keys = [[XF86KbdBrightnessUp]], description = [[Keyboard brightness up]], dispatcher = [[exec]], argument = [[qv-brightness-keyboard up]], repeating = true, locked = true })
qv.bind({ keys = [[XF86KbdBrightnessDown]], description = [[Keyboard brightness down]], dispatcher = [[exec]], argument = [[qv-brightness-keyboard down]], repeating = true, locked = true })
qv.bind({ keys = [[XF86KbdLightOnOff]], description = [[Keyboard backlight cycle]], dispatcher = [[exec]], argument = [[qv-brightness-keyboard cycle]], locked = true })
qv.bind({ keys = [[XF86TouchpadToggle]], description = [[Toggle touchpad]], dispatcher = [[exec]], argument = [[qv-toggle-touchpad]], locked = true })
qv.bind({ keys = [[XF86TouchpadOn]], description = [[Enable touchpad]], dispatcher = [[exec]], argument = [[qv-toggle-touchpad on]], locked = true })
qv.bind({ keys = [[XF86TouchpadOff]], description = [[Disable touchpad]], dispatcher = [[exec]], argument = [[qv-toggle-touchpad off]], locked = true })
qv.bind({ keys = [[ALT + XF86AudioRaiseVolume]], description = [[Volume up precise]], dispatcher = [[exec]], argument = [[qv-swayosd-client --output-volume +1]], repeating = true, locked = true })
qv.bind({ keys = [[ALT + XF86AudioLowerVolume]], description = [[Volume down precise]], dispatcher = [[exec]], argument = [[qv-swayosd-client --output-volume -1]], repeating = true, locked = true })
qv.bind({ keys = [[ALT + XF86MonBrightnessUp]], description = [[Brightness up precise]], dispatcher = [[exec]], argument = [[qv-brightness-display +1%]], repeating = true, locked = true })
qv.bind({ keys = [[ALT + XF86MonBrightnessDown]], description = [[Brightness down precise]], dispatcher = [[exec]], argument = [[qv-brightness-display 1%-]], repeating = true, locked = true })
qv.bind({ keys = [[XF86AudioNext]], description = [[Next track]], dispatcher = [[exec]], argument = [[qv-swayosd-client --playerctl next]], locked = true })
qv.bind({ keys = [[XF86AudioPause]], description = [[Pause]], dispatcher = [[exec]], argument = [[qv-swayosd-client --playerctl play-pause]], locked = true })
qv.bind({ keys = [[XF86AudioPlay]], description = [[Play]], dispatcher = [[exec]], argument = [[qv-swayosd-client --playerctl play-pause]], locked = true })
qv.bind({ keys = [[XF86AudioPrev]], description = [[Previous track]], dispatcher = [[exec]], argument = [[qv-swayosd-client --playerctl previous]], locked = true })
qv.bind({ keys = [[SUPER + XF86AudioMute]], description = [[Switch audio output]], dispatcher = [[exec]], argument = [[qv-audio-output-switch]], locked = true })
