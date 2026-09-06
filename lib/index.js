/**
 * dsh-gpt-icon host half.
 *
 * Re-applies the blue ChatGPT-knot branding to DSH Desktop on every harness
 * boot, so an app update that overwrites `D:\dsh desktop\...` is repaired on
 * the next launch:
 *
 *   - resources/icon.png / icon.ico     window + tray + shortcut icon
 *   - resources/dsh-loader*.gif         splash logo
 *   - resources/splash.html             drop the dark-mode whale filter
 *   - dsh-web-frontend/dist/*           sidebar logo PNGs, favicon, FishLogo
 *   - dsh-client-ui-primitives lib      BrandWordmark whale -> knot
 *   - dsh-skill-badge assets            badge image + shields.io logo
 *   - out/main/index.js                 desktopIconPath -> icon.ico, explicit
 *                                       window.setIcon, /app-icon stays PNG
 *   - DSH Desktop.exe                   RT_ICON/RT_GROUP_ICON replaced by a
 *                                       scheduled-task patcher once the app
 *                                       quits
 *
 * Everything is idempotent (hash / marker checked) and every modification is
 * backed up per app version under <DSH_HOME>/gpt-icon-data/backup/.
 */
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, readdir, writeFile, appendFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const pluginRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const BLUE = "#1E6FEB";
const KNOT_PATH =
  "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z";

const name = "dsh-gpt-icon";
const inject = ["webServer"];

// ---------------------------------------------------------------- utilities

function dataDir() {
  return process.env.DSH_HOME
    ? join(process.env.DSH_HOME, "gpt-icon-data")
    : join(homedir(), ".dsh", "gpt-icon-data");
}

async function log(message) {
  const line = `[${new Date().toISOString()}] [dsh-gpt-icon] ${message}\n`;
  try {
    await mkdir(dataDir(), { recursive: true });
    await appendFile(join(dataDir(), "gpt-icon.log"), line);
  } catch { /* logging is best effort */ }
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function safeName(path) {
  return path.replace(/[\\/:*?"<>|]/g, "_");
}

async function backupOnce(target, appVersion) {
  if (!existsSync(target)) return null;
  const backupRoot = join(dataDir(), "backup", appVersion || "unknown");
  const destination = join(backupRoot, safeName(target));
  if (!existsSync(destination)) {
    await mkdir(dirname(destination), { recursive: true });
    await copyFile(target, destination);
  }
  return destination;
}

// ------------------------------------------------------------ install paths

function findInstallRoot() {
  const override = process.env.DSH_GPT_ICON_ROOT;
  if (override && existsSync(join(override, "DSH Desktop.exe"))) return override;
  // The harness Node is bundled at <root>\resources\app\node_modules\node\bin\node.exe.
  let dir = dirname(process.execPath);
  for (let depth = 0; depth < 8; depth++) {
    if (existsSync(join(dir, "DSH Desktop.exe")) && existsSync(join(dir, "resources", "app", "package.json"))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const guess = "D:\\dsh desktop";
  if (existsSync(join(guess, "DSH Desktop.exe"))) return guess;
  return null;
}

// ------------------------------------------------------------- patch tables

function buildPatchPlan(installRoot, appVersion) {
  const appDir = join(installRoot, "resources", "app");
  const resDir = join(installRoot, "resources");
  const frontendDist = join(appDir, "node_modules", "@deepseek-ai", "dsh-web-frontend", "dist");
  const primitivesLib = join(appDir, "node_modules", "@deepseek-ai", "dsh-client-ui-primitives", "lib", "index.js");
  const badgeAssets = join(appDir, "node_modules", "@deepseek-ai", "dsh-skill-badge", "assets");
  const mainJs = join(appDir, "out", "main", "index.js");

  return [
    // ---- straight asset copies ----
    { kind: "file", name: "window/tray icon.png", target: join(resDir, "icon.png"), asset: "icon.png" },
    { kind: "file", name: "multi-size icon.ico", target: join(resDir, "icon.ico"), asset: "icon.ico", create: true },
    { kind: "file", name: "splash loader (light)", target: join(resDir, "dsh-loader.gif"), asset: "dsh-loader.gif" },
    { kind: "file", name: "splash loader (dark)", target: join(resDir, "dsh-loader-dark.gif"), asset: "dsh-loader-dark.gif" },
    { kind: "file", name: "web manifest logo", target: join(frontendDist, "dsh-desktop-logo.png"), asset: "dsh-desktop-logo.png" },
    { kind: "file", name: "sidebar logo (light)", target: join(frontendDist, "dsh-desktop-logo-light.png"), asset: "dsh-desktop-logo-light.png" },
    { kind: "file", name: "sidebar logo (dark)", target: join(frontendDist, "dsh-desktop-logo-dark.png"), asset: "dsh-desktop-logo-dark.png" },
    { kind: "file", name: "web favicon.svg", target: join(frontendDist, "favicon.svg"), asset: "chatgpt-blue-hollow.svg" },
    { kind: "file", name: "skill badge image", target: join(badgeAssets, "dsh-badge.png"), asset: "dsh-badge.png" },

    // ---- text patches (marker = knot path or explicit marker string) ----
    {
      kind: "text",
      name: "BrandWordmark whale (client-ui-primitives)",
      target: primitivesLib,
      marker: KNOT_PATH,
      ops: [
        {
          label: "wordmark whale -> knot",
          type: "regex",
          pattern: '\\s*jsx\\("g", \\{\\s*clipPath: "url\\(#dsh-wordmark-whale-clip\\)",\\s*children: jsx\\("path", \\{\\s*d: "[^"]+",\\s*fill: "currentColor"\\s*\\}\\)\\s*\\}\\),',
          flags: "s",
          replace: `\n\t\t\tjsx("path", {\n\t\t\t\td: "${KNOT_PATH}",\n\t\t\t\tfill: "${BLUE}"\n\t\t\t}),`
        }
      ]
    },
    {
      kind: "text",
      name: "skill badge shields.io logo",
      target: join(badgeAssets, "dsh-badge.md"),
      marker: "logoColor=1E6FEB",
      ops: [
        { label: "badge logo=deepseek -> logo=openai", type: "literal", find: "logo=deepseek&logoColor=white", replace: "logo=openai&logoColor=1E6FEB" }
      ]
    },
    {
      kind: "text",
      name: "splash dark-mode filter",
      target: join(resDir, "splash.html"),
      marker: "gpt-icon",
      ops: [
        {
          label: "remove whale brightness filter",
          type: "literal",
          find: "filter: brightness(2.4) saturate(0.72) drop-shadow(0 0 7px rgba(111, 134, 255, 0.16));",
          replace: "/* gpt-icon: whale filter removed */"
        }
      ]
    },
    {
      kind: "text",
      name: "main process icon wiring",
      target: mainJs,
      marker: 'join(process.resourcesPath, "icon.ico")',
      checkSyntax: true,
      ops: [
        {
          label: "desktopIconPath -> icon.ico",
          type: "literal",
          find: 'return app.isPackaged ? join(process.resourcesPath, "icon.png") : join(app.getAppPath(), "build", "app-icon.png");',
          replace: 'return app.isPackaged ? join(process.resourcesPath, "icon.ico") : join(app.getAppPath(), "build", "app-icon.png");'
        },
        {
          label: "/app-icon keeps serving PNG",
          type: "literal",
          find: "appIconPath: desktopIconPath(),",
          replace: 'appIconPath: app.isPackaged ? join(process.resourcesPath, "icon.png") : desktopIconPath(),'
        },
        {
          label: "explicit window.setIcon on win32",
          type: "literal",
          find: '  if (process.platform === "darwin") {\n    window.setWindowButtonVisibility(true);',
          replace: '  if (process.platform === "win32") window.setIcon(desktopIconPath());\n  if (process.platform === "darwin") {\n    window.setWindowButtonVisibility(true);'
        }
      ]
    },

    // ---- minified frontend bundle: FishLogo + wordmark whale ----
    {
      kind: "bundleFish",
      name: "FishLogo (web-frontend bundle)",
      dir: join(frontendDist, "assets"),
      pattern: /^index-.+\.js$/
    }
  ];
}

// ------------------------------------------------------------ patch engines

async function applyFileOp(item, appVersion, results) {
  if (!existsSync(item.target)) {
    if (item.create) {
      await mkdir(dirname(item.target), { recursive: true });
      await copyFile(join(pluginRoot, "assets", item.asset), item.target);
      results.push({ name: item.name, state: "ok", detail: "created" });
      return;
    }
    results.push({ name: item.name, state: "skipped", detail: "target missing (upstream changed?)" });
    return;
  }
  const [targetHash, assetHash] = await Promise.all([
    readFile(item.target).then((b) => sha256(b)),
    readFile(join(pluginRoot, "assets", item.asset)).then((b) => sha256(b))
  ]);
  if (targetHash === assetHash) {
    results.push({ name: item.name, state: "ok", detail: "already applied" });
    return;
  }
  await backupOnce(item.target, appVersion);
  await copyFile(join(pluginRoot, "assets", item.asset), item.target);
  results.push({ name: item.name, state: "ok", detail: "replaced" });
}

async function applyTextOp(item, appVersion, results) {
  if (!existsSync(item.target)) {
    results.push({ name: item.name, state: "skipped", detail: "target missing (upstream changed?)" });
    return;
  }
  const original = await readFile(item.target, "utf8");
  if (original.includes(item.marker)) {
    results.push({ name: item.name, state: "ok", detail: "already applied" });
    return;
  }
  let text = original;
  const applied = [];
  for (const op of item.ops) {
    if (op.type === "literal") {
      if (!text.includes(op.find)) continue;
      text = text.split(op.find).join(op.replace);
      applied.push(op.label);
    } else {
      const re = new RegExp(op.pattern, op.flags ?? "");
      if (!re.test(text)) continue;
      text = text.replace(re, op.replace);
      applied.push(op.label);
    }
  }
  if (!applied.length) {
    results.push({ name: item.name, state: "skipped", detail: "no pattern matched (upstream changed?)" });
    return;
  }
  const backup = await backupOnce(item.target, appVersion);
  await writeFile(item.target, text, "utf8");
  if (item.checkSyntax) {
    const check = spawnSync(process.execPath, ["--check", item.target], { timeout: 30000 });
    if (check.status !== 0) {
      if (backup) await copyFile(backup, item.target);
      results.push({ name: item.name, state: "error", detail: `syntax check failed, restored backup: ${String(check.stderr).slice(0, 200)}` });
      return;
    }
  }
  results.push({ name: item.name, state: "ok", detail: `patched: ${applied.join("; ")}` });
}

async function applyBundleFishOp(item, appVersion, results) {
  if (!existsSync(item.dir)) {
    results.push({ name: item.name, state: "skipped", detail: "assets dir missing" });
    return;
  }
  const files = (await readdir(item.dir)).filter((f) => item.pattern.test(f));
  if (!files.length) {
    results.push({ name: item.name, state: "skipped", detail: "no index-*.js bundle found" });
    return;
  }
  for (const file of files) {
    const target = join(item.dir, file);
    const original = await readFile(target, "utf8");
    if (original.includes(KNOT_PATH)) {
      results.push({ name: item.name, state: "ok", detail: `${file}: already applied` });
      return;
    }
  }
  for (const file of files) {
    const target = join(item.dir, file);
    const original = await readFile(target, "utf8");
    const fishStart = original.indexOf("function md(");
    if (fishStart < 0) {
      results.push({ name: item.name, state: "skipped", detail: `${file}: FishLogo (function md) not found` });
      continue;
    }
    const aliasMatch = original.slice(fishStart, fishStart + 400).match(/(\w+)\.jsx\(/);
    const alias = aliasMatch ? aliasMatch[1] : "d";
    const wordmarkStart = original.indexOf(`function gd(`, fishStart);
    if (wordmarkStart < 0 || wordmarkStart <= fishStart || wordmarkStart - fishStart > 4096) {
      results.push({ name: item.name, state: "skipped", detail: `${file}: cannot bound FishLogo function` });
      continue;
    }
    const newFish =
      `function md({size:n=24,className:i}){return ${alias}.jsx("svg",{width:n,height:n,className:i,viewBox:"0 0 24 24",fill:"none","aria-hidden":"true",` +
      `children:${alias}.jsx("path",{d:"${KNOT_PATH}",fill:"${BLUE}"})})}`;
    let text = original.slice(0, fishStart) + newFish + original.slice(wordmarkStart);
    const whaleRe = new RegExp(
      `${alias}\\.jsx\\("g",\\{clipPath:"url\\(#dsh-wordmark-whale-clip\\)",children:${alias}\\.jsx\\("path",\\{d:"[^"]+",fill:"currentColor"\\}\\)\\}\\)`
    );
    if (whaleRe.test(text)) {
      text = text.replace(whaleRe, `${alias}.jsx("path",{d:"${KNOT_PATH}",fill:"${BLUE}"})`);
    }
    const backup = await backupOnce(target, appVersion);
    await writeFile(target, text, "utf8");
    const check = spawnSync(process.execPath, ["--check", target], { timeout: 30000 });
    if (check.status !== 0) {
      if (backup) await copyFile(backup, target);
      results.push({ name: item.name, state: "error", detail: `${file}: syntax check failed, restored` });
      return;
    }
    results.push({ name: item.name, state: "ok", detail: `${file}: FishLogo + wordmark replaced` });
    return; // patch only the primary index bundle
  }
}

// ------------------------------------------------------------- exe handling

function exeStatePath() {
  return join(dataDir(), "exe-state.json");
}

async function readExeState() {
  try {
    return JSON.parse(await readFile(exeStatePath(), "utf8"));
  } catch {
    return {};
  }
}

const EXE_PATCH_TASK = "DSH GptIcon ExePatch";

async function scheduleExePatch(installRoot) {
  // The patcher must outlive the harness process (it acts after the app
  // quits), so it runs as a one-shot Scheduled Task instead of a detached
  // child: Task Scheduler owns the process tree, and its default
  // "do not start a new instance" policy deduplicates concurrent runs.
  // schtasks limits /TR to 261 chars, so the real command lives in a small
  // cmd wrapper that this function regenerates on every schedule.
  const wrapperPath = join(dataDir(), "run-patcher.cmd");
  const wrapper = [
    "@echo off",
    `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "${join(pluginRoot, "bin", "patch-exe-icon.ps1")}" -Exe "${join(installRoot, "DSH Desktop.exe")}" -Ico "${join(pluginRoot, "assets", "icon.ico")}" -DataDir "${dataDir()}"`,
    ""
  ].join("\r\n");
  await writeFile(wrapperPath, wrapper, "utf8");
  const create = spawnSync("schtasks", [
    "/Create", "/F", "/TN", EXE_PATCH_TASK, "/TR", `"${wrapperPath}"`, "/SC", "ONCE", "/ST", "23:59"
  ], { timeout: 30000 });
  if (create.status !== 0) {
    throw new Error(`schtasks /Create failed: ${String(create.stderr || create.stdout).slice(0, 200)}`);
  }
  const run = spawnSync("schtasks", ["/Run", "/TN", EXE_PATCH_TASK], { timeout: 30000 });
  if (run.status !== 0) {
    throw new Error(`schtasks /Run failed: ${String(run.stderr || run.stdout).slice(0, 200)}`);
  }
  return "scheduled task started";
}

async function checkExe(installRoot, results) {
  const exePath = join(installRoot, "DSH Desktop.exe");
  if (!existsSync(exePath)) {
    results.push({ name: "exe embedded icon", state: "skipped", detail: "exe not found" });
    return;
  }
  const current = sha256(await readFile(exePath));
  const state = await readExeState();
  // The watcher records the hash via PowerShell's Get-FileHash (uppercase);
  // compare case-insensitively so both sides agree.
  if (current.toLowerCase() === String(state.exeSha256 ?? "").toLowerCase()) {
    results.push({ name: "exe embedded icon", state: "ok", detail: "already patched" });
    return;
  }
  const detail = await scheduleExePatch(installRoot);
  results.push({ name: "exe embedded icon", state: "pending", detail: `${detail}; applies after the app fully exits` });
}

// ------------------------------------------------------------------ repair

let repairRunning = false;
let lastResult = null;

async function repairNow() {
  if (repairRunning) return lastResult ?? { items: [{ name: "repair", state: "busy" }] };
  repairRunning = true;
  const results = [];
  try {
    const installRoot = findInstallRoot();
    if (!installRoot) {
      results.push({ name: "install root", state: "error", detail: "could not locate DSH Desktop install (set DSH_GPT_ICON_ROOT)" });
      return { installRoot: null, items: results };
    }
    let appVersion = "unknown";
    try {
      const pkg = JSON.parse(await readFile(join(installRoot, "resources", "app", "package.json"), "utf8"));
      appVersion = pkg.version ?? "unknown";
    } catch { /* keep unknown */ }
    await mkdir(dataDir(), { recursive: true });
    const plan = buildPatchPlan(installRoot, appVersion);
    for (const item of plan) {
      try {
        if (item.kind === "file") await applyFileOp(item, appVersion, results);
        else if (item.kind === "text") await applyTextOp(item, appVersion, results);
        else if (item.kind === "bundleFish") await applyBundleFishOp(item, appVersion, results);
      } catch (error) {
        results.push({ name: item.name, state: "error", detail: error.message });
      }
    }
    await checkExe(installRoot, results);
    const summary = { installRoot, appVersion, at: new Date().toISOString(), items: results };
    lastResult = summary;
    for (const item of results) await log(`${item.state.toUpperCase().padEnd(7)} ${item.name}: ${item.detail}`);
    return summary;
  } finally {
    repairRunning = false;
  }
}

// ------------------------------------------------------------- plugin entry

const ROUTE_STATUS = "/gpt-icon/status";
const ROUTE_REPAIR = "/gpt-icon/repair";

function sendJson(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body, null, 2));
}

function apply(ctx) {
  let server = null;
  try { server = ctx.get("webServer") ?? null; } catch { /* service unavailable */ }
  ctx.effect(() => {
    const offs = [];
    if (server) {
      offs.push(server.register({
        kind: "exact",
        path: ROUTE_STATUS,
        handler: (req, res) => {
          sendJson(res, 200, { ok: true, lastResult, exeState: existsSync(exeStatePath()) ? "patched" : "stock" });
        }
      }));
      offs.push(server.register({
        kind: "exact",
        path: ROUTE_REPAIR,
        handler: async (req, res) => {
          const summary = await repairNow();
          sendJson(res, 200, summary);
        }
      }));
    } else {
      log("webServer service unavailable; HTTP routes disabled");
    }
    // Repair shortly after boot so the harness is not slowed down, and the
    // splash (read by the main process very early) is already correct on the
    // *next* launch after an update.
    const timer = setTimeout(() => {
      repairNow().catch((error) => log(`repair failed: ${error.stack ?? error}`));
    }, 3000);
    return () => {
      clearTimeout(timer);
      for (const off of offs) off();
    };
  }, "dsh-gpt-icon: repair + routes");
}

export { apply, inject, name };
