# Mochi Island

A Mac notch pet. The shipping app is Swift plus the web UI in `web/`. There is no local web server.

## Run

`Scripts/build-app.sh` builds `island/MochiIsland.app`. Open that app. `Scripts/notarize.sh` signs a DMG when `DEVELOPER_ID_APP` is set, and notarizes it when `NOTARY_PROFILE` is set.

`swift run -c debug MochiCoreChecks` runs the play, save, and hook checks.

## Layout

- `Sources/MochiCore/` — pet rules, save files, Cursor hook install. No AppKit.
- `Sources/MochiIsland/` — notch window and the message bridge.
- `Sources/MochiHookCLI/` — the program Cursor hooks run. If it fails, it still exits 0.
- `web/island.html`, `web/island.css`, `web/island.js`, `web/pets/`, `web/status/` — copied into the app as `Resources/Web`.
- `Tests/MochiCoreChecks/main.swift` — the checks.

## Messages

The page talks to Swift only through `webkit.messageHandlers.island`. Each call includes `action` and `rpc`. Swift answers with `window.mochiReply(rpc, json)`.

| action | purpose |
|---|---|
| `hotRects` | click-through rectangles |
| `glass` | glass plates behind bubbles and cards |
| `savePrefs` | position, color, sound, look |
| `getState` | pet snapshot |
| `play` | play with the pet |
| `getTasks` | current Cursor tasks |
| `cursorLink` | connect or disconnect hooks. `linkAction` is `connect`, `disconnect`, or `status`. First connect needs `acknowledged: true` after the privacy line is shown |
| `cursorChoice` | `permission` writes `~/.cursor/mochi-island-reply.json`. Anything else opens Cursor |
| `setScan` | optional local file notice. Default off. It records names and times, not chat text |

Do not add `fetch` to a localhost URL. Do not add a new action without a row in this table.

Swift watches `~/.cursor/mochi-island-tasks.json` and calls `window.pushTasks(tasks, state)` when that file changes. The page does not send `pushTasks`. `getState` and `getTasks` still poll every 5 seconds as a fallback.

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

## UI

Collapsed: pet and English bubble. Click either to toggle the stats card. The gear opens settings. Pet and bubble offsets are independent. Position sliders do not move the cards. `placeCards()` runs on the next popup.

Chinese uses PingFang SC. Task bubbles use the GIFs in `web/status/`. Looks are one Mochi set, 16 slots, 4 per row. Colors are eight swatches plus hex text. Never use `<input type="color">`.

## Release

Bundle ID `com.mochiisland.mac`, the marketing version, and `LSMinimumSystemVersion` stay in `island/Info.plist` and match the Swift package platform (`macOS 26`). Do not turn ATS off. Do not ship an ad-hoc signature. A change in `Sources/MochiCore/` or `Sources/MochiIsland/AppSession.swift` needs a matching change in `Tests/MochiCoreChecks/main.swift`.

Before handing off a build, search `Sources` and `web/island.*` for `127.0.0.1`, `8765`, `fetch(`, `python3`, `osascript`, `NSAllowsArbitraryLoads`, and `killall`. Those strings should not be there. `swift run -c debug MochiCoreChecks` should pass, and the app should open from the built `.app` without this repo.

## Cursor Cloud specific instructions

Cloud Agent VMs are Linux. The environment puts Swift 6.2.4 on `PATH` (`/usr/local/bin/swift`, toolchain under `/opt/swift`). That matches `swift-tools-version: 6.2`. Do not install another toolchain.

`swift run -c debug MochiCoreChecks` is the check to run here. It covers play, sleep, feeding, saves, hook install, and the task-file watch. `swift build --product MochiHookCLI` also builds on Linux. Task watches use inotify on Linux, and JSON replace uses `rename`, because Swift's `replaceItemAt` deletes the destination and then fails. macOS still uses `DispatchSource` and `replaceItemAt`.

`swift build --product MochiIsland` and `Scripts/build-app.sh` need macOS. They link AppKit, WebKit, and ServiceManagement, then sign `island/MochiIsland.app`. Leave the macOS 26 platform as it is.

The page has no dev server. Open `web/island.html` in a browser to review layout. Play, feeding, and Cursor linking still need the Mac app's WebKit bridge. Do not add a local server to stand in for it.
