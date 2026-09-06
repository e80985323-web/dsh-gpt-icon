# dsh-gpt-icon

[![CI](https://github.com/OWNER/dsh-gpt-icon/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/dsh-gpt-icon/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)]()

让 **DSH Desktop**（DeepSeek Harness 桌面客户端）的图标保持为透明镂空的蓝色 ChatGPT 结形（`#1E6FEB`），并且**在应用版本更新后自动恢复**。

| 原版 | dsh-gpt-icon |
|:---:|:---:|
| ![before](docs/icon-before.png) | ![after](docs/icon-after.png) |

覆盖范围：应用图标（窗口/任务栏/托盘）、启动闪屏、侧边栏 logo、favicon、界面内 FishLogo/BrandWordmark、技能徽章、EXE 内嵌图标。

[English](README.en.md)

---

## 为什么需要它

DSH Desktop 的更新会整体替换安装目录（`D:\dsh desktop`），任何直接改文件的美化都会在下次更新后被覆盖。本插件把图标改造封装成一个 **DeepSeek Harness 插件**：

- 插件本体安装在与安装目录隔离的 harness 数据目录（`%DSH_HOME%\local-plugins`），更新永不触碰；
- 每次应用启动时**幂等修复**：逐项比对哈希/标记，只重写被覆盖的文件；
- **EXE 内嵌图标**通过计划任务延迟补丁：备份 → 制作补丁副本 → 等待应用正常退出 → 换入 → 刷新 shell 图标缓存。

## 安装

要求：Windows 10/11，DSH Desktop ≥ 0.7.x，Windows PowerShell 5+。

```powershell
git clone https://github.com/OWNER/dsh-gpt-icon.git
cd dsh-gpt-icon
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1
```

然后**完整退出** DSH Desktop（托盘 → 退出）并重新启动。EXE 内嵌图标会在你第一次完整退出后的下一次启动生效。

`install.ps1` 做了三件事：把插件复制到 `%DSH_HOME%\local-plugins\dsh-gpt-icon`；在 `%DSH_HOME%\profiles\web\package.json` 里登记 `file:` 依赖并加入 bundles 列表；在 `profiles\web\node_modules` 放一份实体副本供本次加载。卸载：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\install.ps1 -Uninstall
```

<details>
<summary>手动安装（不想跑脚本）</summary>

1. 复制 `lib/ bin/ assets/ package.json cordis.patch.yml` 到 `%DSH_HOME%\local-plugins\dsh-gpt-icon\`；
2. 编辑 `%DSH_HOME%\profiles\web\package.json`：
   - `dependencies` 加 `"dsh-gpt-icon": "file:../../local-plugins/dsh-gpt-icon"`；
   - `dsh.profile.bundles` 数组加 `"dsh-gpt-icon"`；
3. 把整个插件目录再复制一份到 `%DSH_HOME%\profiles\web\node_modules\dsh-gpt-icon`；
4. 完整重启 DSH Desktop。

</details>

## 更新后的时间线

| 时机 | 发生什么 |
|---|---|
| DSH 自动更新完成 | 安装目录被还原成官方资源，界面变回鲸鱼 |
| 更新后第一次启动 | 插件自动修复所有资源与 JS 补丁；同时安排 exe 补丁任务 |
| 你完整退出一次（托盘 → 退出） | 监视器换入补丁好的 EXE，刷新图标缓存 |
| 下一次启动 | 全部生效；若固定任务栏图标未刷新，取消固定后重新固定一次 |

## 手动控制

- `GET http://127.0.0.1:<harness端口>/gpt-icon/status` — 上次修复结果
- `GET|POST .../gpt-icon/repair` — 立即重新修复
- 日志：`%DSH_HOME%\gpt-icon-data\gpt-icon.log`
- 每个版本的原始文件备份：`%DSH_HOME%\gpt-icon-data\backup\<版本>\`

## 自定义

想换颜色或图案：改 `assets/chatgpt-blue-hollow.svg`（或重新跑 `tools/build-assets.ps1 -SvgPath <你的svg>`，它会用 headless Edge 栅格化并重新生成 PNG/ICO/GIF/徽章全套），然后重启 DSH 或调用 `/gpt-icon/repair`。技术细节（各条图标链路、补丁点、踩坑记录）见 [docs/patch-notes.md](docs/patch-notes.md)。

## 卸载与还原

`tools\install.ps1 -Uninstall` 移除插件注册与文件。要还原官方图标，把 `%DSH_HOME%\gpt-icon-data\backup\<版本>\` 里的备份拷回原位（EXE 用 `backup\exe\` 里对应哈希的 `.backup`），再删除 `gpt-icon-data`。

## 免责声明

本插件会修改 DSH Desktop 安装目录内的文件及 EXE 资源（均先自动备份）。仅供个人美化，风险自担；与 DeepSeek、OpenAI 均无关联。图标基于 OpenAI 公开的 logo 路径数据，版权归 OpenAI 所有，请勿用于商标用途。
