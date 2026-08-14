# Changelog

## 0.2.2 — 2026-08-14

- Add Expo / Obraz / Optika dial panels with AUTO/MAN toggles.
- Add per-panel presets persisted to Application Support.
- Add factory preset `rrc_base` (1/60, ISO 400, brightness 48, focus 68, WB 4200 K) applied automatically on helper startup.
- Invert focus dial so higher values focus nearer.
- Invert white-balance arc color gradient.
- Expose pan, tilt, and backlight when the camera reports them.

## 0.2.1 — 2026-08-14

- Compact the OBS browser dock UI for ~450×320 panels.
- Collapse the header into a single status row.
- Render controls as dense single-line rows (label / slider / value).
- Keep action buttons pinned while allowing the control list to scroll.

## 0.1.1 — 2026-07-19

- Fixed an infinite loop while parsing a composite USB device with non-video interfaces before its UVC control interface.
- Parse the configuration descriptor while its owning IOUSB device interface is still valid.
- Bound descriptor traversal by `wTotalLength` and validate every `bLength`.
- Keep the first matching UVC control interface instead of leaking and replacing it during enumeration.
- Add a fallback open/request/close sequence for devices that reject a direct UVC request.
- Verified all exposed controls as supported on a connected Razer Kiyo V2 X (USB VID `0x1532`, PID `0x0E0C`) on macOS 26.5.2.

## 0.1.0 — 2026-07-19

- Initial OBS browser dock and macOS menu-bar helper.
