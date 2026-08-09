# qvOS Weather Workflow

Read this file completely when changing weather status, icons, provider
requests, or Waybar weather consumers.

`qvcore/weather/` owns the weather capability. Native commands are
`qv-weather-icon` and `qv-weather-status`; matching `omarchy-weather-*` names
are metadata-free compatibility adapters only. `waybar` is the native JSON
presentation owner and calls only `qv-weather-icon`.

- Use the fixed HTTPS wttr.in JSON endpoint with short connection and total
  timeouts plus a one-megabyte response limit. Accept no URL or query input.
- Validate the complete JSON fields before formatting. Treat provider,
  transport, schema, time, and parsing failures as unavailable; never emit
  partial or shell-interpreted provider data.
- Derive an icon and complete status from one response. Do not make a second
  request for the icon inside status.
- Keep direct icon failure silent for Waybar. Status prints exactly
  `Weather unavailable` and returns failure so notifications remain truthful.
- Existing exact Waybar command literals migrate through the shared native
  config owner. Preserve customized or absent weather configuration.

Run `qvcore/weather/check`, `qvos-weather-test.sh`, Waybar, config migration,
CLI, product, upstream-overlay, Bash syntax, ShellCheck, and the full qvOS
suite. Use provider fixtures for behavior tests; do not depend on the live
network or location.
