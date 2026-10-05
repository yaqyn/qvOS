# Public README Presentation

The root README describes the current qvOS product and links detailed lifecycle
requirements to their native owners. Keep base capabilities, optional software,
and verified release availability distinct. Never describe a successful ISO
build or diagnostic installation as a confirmed public release.

Use the Yaqyn red/grayscale palette for documentation artwork. The Branding
owner's vector masters remain authoritative; a documentation composition may
embed their paths, record its source hash, and never become another product
master. The hero is a self-contained SVG with accessible title and description.

Screenshots must come from the real current interface and be inspected before
publication. Capture with the native screenshot route, exclude unrelated apps
and private information, and caption the actual surface shown. Do not present
wallpapers or mockups as installed desktop evidence. Keep original screenshot
pixels; terminal font and window size may be set for capture without changing
user configuration.

`launcher-system.png` shows the deployed compiled public launcher captured on
2026-10-05 with its verified source digest
`b83f407779ad2a8cbca1dbf4a47f777aaba7c00f74126b8bb3b4c9e70857efd6`.
The capture used a temporary curl resolver override because the host network
returned a negative DNS answer; the payload came from `qvos.yaqyn.dev`.

Before publication, check local links, CLI examples, SVG rendering, screenshot
privacy, and `git diff --check`. Documentation-only changes do not require a
Worker redeployment or live desktop installation.
