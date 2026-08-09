/**
 * Sync Pi's light/dark theme with the active qvOS theme.
 *
 * qvOS retains ~/.config/omarchy/current/theme as its documented external-theme
 * compatibility ABI.
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = process.env.HOME;
const lightModePath = home
  ? join(home, ".config/omarchy/current/theme/light.mode")
  : null;

function qvosPiTheme(): "light" | "dark" {
  return lightModePath && existsSync(lightModePath) ? "light" : "dark";
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  const stopWatching = () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  };

  pi.on("session_start", (_event, ctx) => {
    stopWatching();
    let currentTheme = qvosPiTheme();
    ctx.ui.setTheme(currentTheme);

    intervalId = setInterval(() => {
      const nextTheme = qvosPiTheme();
      if (nextTheme !== currentTheme) {
        currentTheme = nextTheme;
        ctx.ui.setTheme(currentTheme);
      }
    }, 2000);
  });

  pi.on("session_shutdown", stopWatching);
}
