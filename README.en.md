# dsh-gpt-icon

[![CI](https://github.com/OWNER/dsh-gpt-icon/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/dsh-gpt-icon/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)]()

Keep the **DSH Desktop** (DeepSeek Harness desktop client) icon as the transparent blue ChatGPT knot (`#1E6FEB`) — and **restore it automatically after every app update**.

| Stock | dsh-gpt-icon |
|:---:|:---:|
| ![before](docs/icon-before.png) | ![after](docs/icon-after.png) |

[中文说明](README.md)

DSH Desktop updates replace the whole install directory (`D:\dsh desktop`), wiping any file-level customization. This project packages the icon rebrand as a **DeepSeek Harness plugin**:

- The plugin itself lives in the harness data directory (`%DSH_HOME%\local-plugins`), which updates never touch.
- On every app start it runs an **idempotent repair**: hash/marker-checked, rewriting only what the update overwrote — window/taskbar/tray icon, splash loader, sidebar logos, favicon, in-app FishLogo/BrandWordmark, skill badge, and the main-process icon wiring.
- The **EXE embedded icon** (used by pinned taskbar / Start menu) is patched by a Scheduled-Task helper that waits for the app to quit normally, then swaps in the patched binary and refreshes the shell icon cache.

## Install

Requires Windows 10/11, DSH Desktop ≥ 0.7.x, Windows PowerShell 5+.

```powershell
git clone https://github.com/OWNER/dsh-gpt-icon.git
cd dsh-gpt-icon
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
```

Then fully quit DSH Desktop (tray → Exit) and start it again. The EXE icon lands after your next full quit/restart cycle.

`tools\install.ps1 -Uninstall` removes the plugin. Manual install steps are in the [Chinese README](README.md).

## After an update

1. DSH updates → branding reverts to the whale.
2. Next launch → the plugin re-applies everything and arms the EXE patch task.
3. You fully quit once → the patched EXE is swapped in, icon cache refreshed.
4. Next launch → all blue. (If a pinned taskbar icon is stale, unpin and re-pin.)

## Manual control

- `GET http://127.0.0.1:<harness port>/gpt-icon/status` — last repair report
- `GET|POST .../gpt-icon/repair` — force a repair pass
- Log: `%DSH_HOME%\gpt-icon-data\gpt-icon.log`
- Per-version backups of every replaced file: `%DSH_HOME%\gpt-icon-data\backup\<version>\`

## Customizing

Edit `assets/chatgpt-blue-hollow.svg` (or feed your own SVG to `tools/build-assets.ps1 -SvgPath <file>`) to regenerate the PNG/ICO/GIF/badge set, then restart DSH or call `/gpt-icon/repair`. Technical notes on every icon chain and patch point: [docs/patch-notes.md](docs/patch-notes.md).

## Disclaimer

The plugin modifies files inside the DSH Desktop install directory and EXE resources (always backed up first). Personal cosmetic use only, at your own risk. Not affiliated with DeepSeek or OpenAI; the knot artwork is OpenAI's logo, use it accordingly.
