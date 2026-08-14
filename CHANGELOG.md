# Changelog

## 0.1.1 — 2026-07-19

- Fixed an infinite loop while parsing a composite USB device with non-video interfaces before its UVC control interface.
- Parse the configuration descriptor while its owning IOUSB device interface is still valid.
- Bound descriptor traversal by `wTotalLength` and validate every `bLength`.
- Keep the first matching UVC control interface instead of leaking and replacing it during enumeration.
- Add a fallback open/request/close sequence for devices that reject a direct UVC request.
- Verified all exposed controls as supported on a connected Razer Kiyo V2 X (USB VID `0x1532`, PID `0x0E0C`) on macOS 26.5.2.

## 0.1.0 — 2026-07-19

- Initial OBS browser dock and macOS menu-bar helper.
