import json
import math
import re
import subprocess
from pathlib import Path

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
from gi.repository import Gdk, GLib, Gtk

SIDEBAR_APP_ID = "org.qvos.codex-sidebar"
CORNER_APP_ID = "org.qvos.codex-sidebar-corner"
WORKSPACE = "special:qvos-codex-sidebar"
RADIUS = 18
POLL_MS = 100


def hyprctl_json(*args, fallback):
  try:
    result = subprocess.run(
      ["hyprctl", *args, "-j"],
      check=True,
      capture_output=True,
      text=True,
      timeout=0.5,
    )
    return json.loads(result.stdout)
  except Exception:
    return fallback


def hyprctl_dispatch(*args):
  subprocess.run(
    ["hyprctl", "dispatch", *args],
    check=False,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    timeout=0.5,
  )


def read_background():
  candidates = [
    Path.home() / ".config/omarchy/current/theme/ghostty.conf",
    Path.home() / ".config/omarchy/current/theme/waybar.css",
  ]

  for path in candidates:
    try:
      for line in path.read_text(encoding="utf-8").splitlines():
        match = re.search(r"(?:background\s*=\s*|@define-color\s+background\s+)#([0-9a-fA-F]{6})", line)
        if match:
          value = match.group(1)
          return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4))
    except OSError:
      continue

  return (0.03, 0.03, 0.03)


def clients():
  return hyprctl_json("clients", fallback=[])


def first_client_address(app_id):
  return next((item.get("address") for item in clients() if item.get("class") == app_id), None)


def sidebar_geometry():
  client = next((item for item in clients() if item.get("class") == SIDEBAR_APP_ID), None)
  if not client:
    return None

  monitors = hyprctl_json("monitors", fallback=[])
  monitor = next(
    (
      item
      for item in monitors
      if item.get("specialWorkspace", {}).get("name") == WORKSPACE
    ),
    None,
  )
  if not monitor:
    return {"visible": False}

  reserved = monitor.get("reserved") or [0, 0, 0, 0]
  at = client.get("at") or [0, 0]
  size = client.get("size") or [0, 0]
  if len(reserved) < 2 or len(at) < 2 or len(size) < 2:
    return None

  return {
    "visible": True,
    "draw": reserved[1] > 0,
    "x": int(at[0]) + int(size[0]),
    "y": int(at[1]),
  }


class CornerApp(Gtk.Application):
  def __init__(self):
    super().__init__(application_id=CORNER_APP_ID)
    self.window = None
    self.area = None
    self.color = read_background()
    self.active = False
    self.last_position = None

  def do_activate(self):
    self.window = Gtk.ApplicationWindow(application=self)
    self.window.set_decorated(False)
    self.window.set_resizable(False)
    self.window.set_can_focus(False)
    self.window.set_can_target(False)
    self.window.set_default_size(RADIUS, RADIUS)
    self.window.add_css_class("qvos-codex-sidebar-corner")

    self.area = Gtk.DrawingArea()
    self.area.set_content_width(RADIUS)
    self.area.set_content_height(RADIUS)
    self.area.set_can_target(False)
    self.area.set_draw_func(self.draw_corner)
    self.window.set_child(self.area)

    self.apply_css()
    self.window.present()
    GLib.timeout_add(POLL_MS, self.sync)
    self.sync()

  def apply_css(self):
    provider = Gtk.CssProvider()
    css = """
      window.qvos-codex-sidebar-corner,
      window.qvos-codex-sidebar-corner * {
        background: transparent;
        border: none;
        box-shadow: none;
      }
    """
    provider.load_from_data(css.encode("utf-8"))
    Gtk.StyleContext.add_provider_for_display(
      Gdk.Display.get_default(),
      provider,
      Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )

  def draw_corner(self, _area, context, width, height):
    if not self.active:
      return

    radius = min(width, height)
    context.set_source_rgba(*self.color, 1)
    context.move_to(0, 0)
    context.line_to(radius, 0)
    context.arc_negative(radius, radius, radius, -math.pi / 2, -math.pi)
    context.close_path()
    context.fill()

  def set_active(self, active):
    if self.active == active:
      return

    self.active = active
    self.area.queue_draw()

  def position_window(self, geometry):
    address = first_client_address(CORNER_APP_ID)
    if not address:
      return

    position = (geometry["x"], geometry["y"])
    if position == self.last_position:
      return

    hyprctl_dispatch("resizewindowpixel", "exact", str(RADIUS), str(RADIUS), f"address:{address}")
    hyprctl_dispatch("movewindowpixel", "exact", str(geometry["x"]), str(geometry["y"]), f"address:{address}")
    hyprctl_dispatch("setprop", f"address:{address}", "border_size", "0")
    self.last_position = position

  def sync(self):
    geometry = sidebar_geometry()
    if geometry is None:
      self.set_active(False)
      return True

    if not geometry.get("visible", False):
      return True

    self.position_window(geometry)
    self.set_active(bool(geometry.get("draw", False)))
    return True


if __name__ == "__main__":
  raise SystemExit(CornerApp().run())
