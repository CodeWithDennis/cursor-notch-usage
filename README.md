# Cursor Notch Usage

A macOS overlay that shows your **Cursor plan usage** left and right of the laptop notch.

Fully AI-generated with **Grok 4.5 High Fast**.

> **Disclaimer:** This is a rough concept, not a finished product. It barely works, breaks easily, and may misbehave on your machine. **Use at your own risk.** No support, no warranties, no guarantees.

## What it does

- Sits as a black **Dynamic Island / notch** strip on the **primary display** (menu bar screen).
- **Idle:** `Auto XX%` on the left · `API XX%` on the right.
- **Hover:** expands to show plan name (`✦ Ultra`) and billing cycle remaining (`16d`).
- Wings stretch to fit content; the camera cutout stays clear in the middle.
- **Right-click** the island → Quit.
- Refreshes usage from Cursor’s API about every **60 seconds** (local bridge on `:4318`).

No agent list, hooks, or chat monitoring — usage only. Companion to [agent-peekr](https://github.com/CodeWithDennis/agent-peekr).

## Stack

| Piece | Role |
| --- | --- |
| **Swift (AppKit + SwiftUI)** | Notch panel, shape mask, hover, usage wings |
| **Node bridge** (`bridge/`) | Reads local Cursor session + usage API |

If Cursor is signed in on the machine, the bridge reuses that local session for usage — no extra setup.

## Install

### DMG (recommended)

```bash
./scripts/make-dmg.sh
open dist/Cursor-Notch-Usage-0.1.0.dmg
```

Drag **Cursor Notch Usage** into Applications, then open it.

> **Gatekeeper:** the app is unsigned. First open: right-click → **Open**, or allow it under **System Settings → Privacy & Security**.

### Install app only

```bash
./scripts/install-app.sh
open "$HOME/Applications/Cursor Notch Usage.app"
```

## Run (dev)

```bash
./scripts/run.sh
```

Builds the Node bridge when needed and launches the Swift app (bridge on `:4318`).

```bash
cd bridge && npm install   # once
```

Requires macOS 14+, Node 22+, Cursor signed in locally, and a notched MacBook (falls back to the menu-bar strip otherwise).

## Interaction

- **Idle** — compact `Auto` / `API` percentages beside the notch.
- **Hover** — plan name + cycle remaining; island width grows to fit.
- **Right-click** — Quit Cursor Notch Usage.
- Stays on the **primary** screen only (the one with the menu bar).

## License

[MIT](LICENSE) © CodeWithDennis
