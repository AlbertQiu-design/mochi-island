# Mochi Island

A Mac menu-bar pet. The shipping app is Swift plus the web UI in `web/`. There is no local web server. The main path is a sidebar capsule and an inward popup.

## Run

`Scripts/build-app.sh` builds `island/MochiIsland.app`. Open that app. `Scripts/notarize.sh` signs a DMG when `DEVELOPER_ID_APP` is set, and notarizes it when `NOTARY_PROFILE` is set.

`swift run -c debug MochiCoreChecks` runs the play, save, and hook checks.

## Layout

- `Sources/MochiCore/` — pet rules, save files, Cursor hook install. No AppKit.
- `Sources/MochiIsland/` — fullscreen click-through panel, the native glass capsule, and the message bridge.
- `Sources/MochiHookCLI/` — the program Cursor hooks run. If it fails, it still exits 0.
- `web/island.html`, `web/island.css`, `web/island.js`, `web/pets/`, `web/status/` — copied into the app as `Resources/Web`.
- `Tests/MochiCoreChecks/main.swift` — the checks.

## Messages

The page talks to Swift only through `webkit.messageHandlers.island`. Each call includes `action` and `rpc`. Swift answers with `window.mochiReply(rpc, json)`.

| action | purpose |
|---|---|
| `hotRects` | click-through rectangles |
| `glass` | glass plates behind bubbles and cards |
| `savePrefs` | dock side, color, sound, look, and the selected slot id when `selected` is sent |
| `getState` | pet snapshot plus `slots`, `selected`, and `dock` |
| `play` | play with the pet |
| `getTasks` | current Cursor tasks |
| `cursorLink` | connect or disconnect hooks. `linkAction` is `connect`, `disconnect`, or `status`. First connect needs `acknowledged: true` after the privacy line is shown |
| `cursorChoice` | Popup approval option. Writes `~/.cursor/mochi-island-reply.json` and the page updates that popup immediately. Does not open an agent window |
| `openAgent` | Blank popup or title click. `source` is `cursor`, `codex`, `grok-bot`, or `mochi`. Opens that app. `mochi` (小猫) stays local and does not open a URL |
| `setScan` | optional local file notice. Default off. It records names and times, not chat text |
| `createSlot` | `source` is `cursor`, `grok-bot`, `mochi`, or `codex`. Appends a dialogue slot whose face follows that source. Does not write the task file |

Do not add `fetch` to a localhost URL. Do not add a new action without a row in this table.

Swift watches `~/.cursor/mochi-island-tasks.json` and calls `window.pushTasks(tasks, state)` when that file changes. The page does not send `pushTasks`. `getState` and `getTasks` still poll every 5 seconds as a fallback.

The capsule is native AppKit. Swift also calls `window.applyCapsuleChrome(info)` with CSS-pixel frames and `window.applyCapsuleEvent({kind})` for `select`, `created`, and `settings`. Those are not page-to-Swift actions.

## Play

Rules live in `Sources/MochiCore/PetEngine.swift`. The page only draws them.

- Hunger, energy, and happiness still decay on the old intervals.
- Play is the only manual action. There is no Feed button.
- One finished Cursor task feeds the pet once. A failed task does not. The task id is stored, and only the latest 500 are kept.
- Hunger at 95, or energy at 0, makes the pet sleep. Sleep stops decay. The next finished AI task wakes it. There is no death and no New Pet button.
- Do not write copy that makes the user feel guilty for leaving.

## Data

Writable files go in `~/Library/Application Support/com.mochiisland.mac/` or in `~/.cursor/` under a `mochi-island-` name. Do not write into the app bundle, the repo, or a `.venv`.

JSON writes go to a temporary file, then replace the destination. Before changing `~/.cursor/hooks.json`, copy it to `hooks.json.mochi-island.bak` and only add or remove entries marked `mochi-island`.

The hook command is the `MochiHookCLI` binary inside the app, not `python3`.

## Cursor

Read hook status from `~/.cursor/mochi-island-tasks.json`. Do not scan agent transcripts unless the user turns that switch on, and even then do not copy prompt text into our files.

Do not drive Cursor with AppleScript or Accessibility. Do not start agents with the Cursor SDK.

Prompt and command text are not stored. Permission bubbles only say allow or deny.

Tasks in `~/.cursor/mochi-island-tasks.json` share one schema and include `source`: `cursor`, `codex`, `grok-bot`, or `mochi`. Cursor tasks are written by `MochiHookCLI`. Codex and Grok Bot tasks are written by `Scripts/mochi-upsert-task.sh`. A blank task bubble opens that source. `Codex.app` is not required: when it is missing, Codex opens `https://chatgpt.com/codex`. Grok Bot opens `Grok Bot.app` when that app is installed. `mochi` is the 小猫 desk pet and stays on this Mac.

## UI

Main path: a 68×602 `NSPanel` (borderless, clear, floating, `hidesOnDeactivate=false`, `materialActiveAppearance(.active)`) docked to the right (switchable to the left), 20px from the screen edge. The shell is a 60-wide official Liquid Glass capsule: `.glassEffect(.clear, in: .capsule)`. Do not use `.regular`, tinted glass, CSS faux-glass, `ultraThinMaterial`, or handmade fills. Slots start as four agents (Cursor, Grok Bot, 小猫, Codex) plus a white `plus` `Menu` and white `gearshape` `Button` (six chrome items). Height hugs that list and grows with new agents, capped at 570 / 602. Slots are official `Button`s with 36px Designer faces inside 40pt circles. Selection is `Circle` + `.white.opacity(0.25)` + spring + `matchedGeometryEffect`. Hovering a slot shows a Dock-style Liquid Glass label; a new wait / approval opens a 200px inward glass card. Both use `.glassEffect(.clear)` and a glass caret aimed at that bot. Settings is an independent higher-level panel so Dock / Looks / Colors / Sound / Links receive clicks. The pane switcher is a horizontal `.glassEffect(.clear, in: .capsule)` tab bar: official `Button`s, `Divider` separators, and spring + `matchedGeometryEffect` on a clear `Circle`. Panes are official grouped `Form`s. Do not use titlebar `TabView` chrome. Only the native option buttons confirm a choice. Blank card space and the title call `openAgent`.

Dialogue slots live in `dialogue-slots.json` under Application Support. Slot faces are bundled `web/pets/cursor-*.svg` (cursor-v2), `web/pets/grok-*.svg` (grok-v9), and the full Designer kitten-v1 illustrations `web/pets/kitten-*.png` (wake/work/wait/done). All four seed sources swap wake/work/wait/done from task status. Codex uses the official `circle` symbol until a Designer pack exists.

Chinese uses PingFang SC. Status marks use the GIFs in `web/status/`. Looks in settings are one Mochi set, 16 slots, 4 per row. Colors are eight swatches plus hex text. Never use `<input type="color">`.

## Release

Bundle ID `com.mochiisland.mac`, the marketing version, and `LSMinimumSystemVersion` stay in `island/Info.plist` and match the Swift package platform (`macOS 26`). Do not turn ATS off. Do not ship an ad-hoc signature. A change in `Sources/MochiCore/` or `Sources/MochiIsland/AppSession.swift` needs a matching change in `Tests/MochiCoreChecks/main.swift`.

Before handing off a build, search `Sources` and `web/island.*` for `127.0.0.1`, `8765`, `fetch(`, `python3`, `osascript`, `NSAllowsArbitraryLoads`, and `killall`. Those strings should not be there. `swift run -c debug MochiCoreChecks` should pass, and the app should open from the built `.app` without this repo.
