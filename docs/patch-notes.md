# Patch notes — every icon chain in DSH Desktop and how this plugin touches it

These notes describe DSH Desktop **v0.7.2** (Windows, packaged build with
`--app-path="D:\dsh desktop\resources\app"`, `app.isPackaged === true`). All
patches in `lib/index.js` are marker/hash-guarded so they degrade to a logged
skip — never a crash — when an update changes the upstream code.

## Icon chains

| Surface | Source | How it is branded |
|---|---|---|
| Running window taskbar button | `BrowserWindow({ icon: desktopIconPath() })` → `resources/icon.png` (→ `icon.ico` after patch) + explicit `window.setIcon` | asset copy + `out/main/index.js` literal patch |
| Tray | `new Tray(desktopIconPath())` | same ICO (multi-size: scaling a 512 px PNG makes the tray blurry) |
| Pinned taskbar / Start menu / Explorer | EXE `RT_ICON` / `RT_GROUP_ICON` resources | scheduled-task resource replacement |
| Splash screen | `resources/splash.html` + `dsh-loader(-dark).gif` | GIF asset copy + filter removal in the HTML |
| Sidebar brand mark | `<image href="/dsh-desktop-logo-light.png|dark.png">` served from `dsh-web-frontend/dist` | PNG asset copies |
| Web favicon / PWA manifest | `dist/favicon.svg`, `dist/dsh-desktop-logo.png` | asset copies |
| Hero area `FishLogo` | inlined into the main client bundle `dist/assets/index-<hash>.js` (minified `function md(`) | locate `function md(` → next `function gd(`, splice in a knot `<svg>`; alias (`d.jsx`) detected dynamically |
| `BrandWordmark` whale | `@deepseek-ai/dsh-client-ui-primitives/lib/index.js` (unminified) | regex on the `clipPath: "url(#dsh-wordmark-whale-clip)"` `<g>` |
| Skill badge | `@deepseek-ai/dsh-skill-badge/assets/dsh-badge.png|.md` | pre-baked composite PNG + literal `logo=deepseek` → `logo=openai` |
| `/app-icon` HTTP route | serves `options.appIconPath` **with `content-type: image/png`** | must keep serving a PNG — that is why the main patch re-points `appIconPath` at `icon.png` instead of following `desktopIconPath()` to the ICO |

## Why the EXE patch is deferred

`BeginUpdateResource` cannot modify a running image. The plugin therefore:

1. computes the exe SHA-256 and compares it to `gpt-icon-data/exe-state.json`
   (case-insensitive: PowerShell's `Get-FileHash` emits uppercase, Node's
   `digest("hex")` lowercase — this mismatch cost us one debugging session);
2. on mismatch, writes `run-patcher.cmd` and registers a one-shot Scheduled
   Task (`schtasks /Create /F` + `/Run`). `schtasks /TR` has a **261-character
   limit**, which is why the long PowerShell invocation lives in the wrapper;
   the task's default *do-not-start-a-new-instance* policy deduplicates runs;
3. the patcher (`bin/patch-exe-icon.ps1`) holds a `Local\` mutex, backs up the
   current exe by hash, PE-patches a copy (pure `BeginUpdateResource` — no
   rcedit dependency), then polls until every `DSH Desktop` process has exited
   **without killing anything**, verifies the exe has not changed meanwhile
   (an update while waiting loops back and re-patches), swaps the copy in,
   deletes the classic icon-cache DBs best-effort, broadcasts
   `SHCNE_ASSOCCHANGED`, and records the new hash;
4. re-patching an already-patched exe rebuilds byte-identical resources; the
   patcher treats "hash unchanged" as *already patched*, not as an error.

## Other hard-won details

- The app hides to the tray on close (`preventDefault(); window.hide()`) —
  closing the window is **not** a restart; the splash, window icon and taskbar
  button only refresh on a real process restart.
- The main bundle is loaded from `out/main/index.js` (unminified enough for
  literal anchors like
  `return app.isPackaged ? join(process.resourcesPath, "icon.png") : ...`).
  After every write the plugin runs `node --check` with the bundled Node
  (`process.execPath` inside the harness) and restores the backup on failure.
- `desktopIconPath()` differs per platform/packaging: dev builds look for
  `build/app-icon.png` which does not exist in packaged installs — do not
  create it and expect it to be read.
- The harness entry logs `DSH_HOME`; the plugin derives the install root from
  `process.execPath`
  (`<root>\resources\app\node_modules\node\bin\node.exe`) with a
  `DSH_GPT_ICON_ROOT` override, so it works on any install drive.
- Windows icon cache (`%LocalAppData%\IconCache.db`,
  `iconcache_*.db`) can keep showing the old icon even after a correct swap;
  the patcher clears it best-effort and pokes the shell. A re-pin or reboot
  settles the rest.
- GIFs are generated with WPF `GifBitmapEncoder` — `System.Drawing`'s GIF
  encoder does not preserve alpha (you get a black box).
