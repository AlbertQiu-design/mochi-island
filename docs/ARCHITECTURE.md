# Mochi Island — 可上线架构与差距（2026-10-19）

仓：本机 `~/Projects/PythonTemplate`（尚未推远程；无 GitHub/Origin 仓名）。

## 目标产品

Mac 原生刘海桌宠；养成 + 主流 Agent 状态灯（Cursor / Codex / Cloud…）；可分发 DMG。

## 推荐架构（已基本落地）

```
Cursor/Codex/Cloud hooks ──写──► ~/.cursor/mochi-island-tasks.json
                                         │
                    DispatchSource 推送 ◄──┘（tasks.json 一变就推；5s 轮询兜底）
                                         ▼
MochiIsland.app ── Swift NSPanel + WKWebView（web/）
  MochiCore: PetEngine / TaskReader / HookInstaller
  MochiHookCLI: Cursor hooks 调用的二进制（fail-open）
```

- **不要**再加 localhost Python / Electron。
- Adapter 层：每种 Agent 只写 tasks.json（统一 schema），UI 不关心来源。
- 分发：`Scripts/build-app.sh` → `.app`；`Scripts/notarize.sh` → 签名 + DMG + 公证。

## 现状

| 项 | 状态 |
|----|------|
| Swift 原生 `.app`（无 8765） | ✅ 已有 `island/MochiIsland.app` |
| Cursor hooks → tasks.json | ✅ |
| 气泡 / 权限点选 | ✅ |
| 养成（睡非死；完成任务喂食） | ✅ |
| DMG 脚本 | ✅ 有 |
| Developer ID + 公证 | ❌ 本机 0 个 codesign 身份；`DEVELOPER_ID_APP` / `NOTARY_PROFILE` 未设 |
| 状态延迟 | ✅ `TaskFileWatch` 调 `window.pushTasks`；页面 5s 兜底 |
| Codex / Cloud adapter | ❌ 未做 |
| 远程仓 / CI / PR 流 | ❌ 本地目录，未上 GitHub/Origin |
| macOS 26 平台门槛 | ⚠️ Package.swift 要求 macOS 26，分发面窄 |

## 打通延迟（优先）

1. Hook 写盘后，App 用 `DispatchSource`/`FSEvents` 监视 `mochi-island-tasks.json`，立刻 `getTasks` 推给 WebView。
2. 轮询降为兜底（≥5s）或关掉。
3. 禁止再扫大段 transcript 当主路径（仅用户显式开关）。

## 上线缺口清单

1. Apple Developer ID Application 证书 + notarytool profile  
2. 降 `LSMinimumSystemVersion` / platform 到合理档（若要覆盖更多 Mac）  
3. 推远程仓 → 套用 `docs/VERSION.md`  
4. Codex / Cloud 同 schema adapter  
5. 公证 DMG 冒烟：未签名机器能打开
