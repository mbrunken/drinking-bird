# Drinking Bird 🐦

A small macOS app that keeps pressing **Enter** (or **⌘ + Enter**) for you while a chosen app — by default **Claude** — is in the foreground.

Every time it presses the key, an animated drinking bird in a top hat dips its beak into a glass of water or pecks the Enter key on a little keyboard.

## Features

- Floating window that stays on top, so you can watch the bird while Claude is in front
- Presses **⌘ + Enter** or plain **Enter** at an interval you choose (0.5 – 10 s)
- Only presses when the target app is frontmost — nothing happens in other apps
- Two scenes: **Glass of water** (splash and ripples) or **Keyboard** (the Enter key goes down and lights up)
- Red liquid climbs the bird's neck as the next press approaches
- Counts the presses and shows a status line (waiting / pecking / missing permission)
- All graphics, including the app icon, are drawn in code — no image assets

## Requirements

- macOS 15 or later
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`

## Build

```bash
./build.sh
```

This compiles `Sources/main.swift`, renders the app icon, and creates `Drinking Bird.app` in the project folder.

## Run

```bash
open "Drinking Bird.app"
```

1. Click **Start**.
2. The first time, macOS asks you to allow **Drinking Bird** under **System Settings → Privacy & Security → Accessibility**. Turn it on (the app's **Open Settings** button takes you there).
3. Switch to Claude. The bird starts pecking.
4. Click **Stop** when you're done.

> The build is ad-hoc signed, so after rebuilding, macOS may treat it as a new app. If key presses stop working, turn Drinking Bird off and on again in the Accessibility list (or remove and re-add it).

## Settings

| Setting | What it does |
| --- | --- |
| Dip into | Glass of water or keyboard animation |
| Key | `⌘ + Enter` (default) or `Enter` |
| Every | How often to press, 0.5 – 10 seconds |
| App | Name of the app that must be in front (default `Claude`) |

## Project layout

```
Sources/main.swift     The app: keypress logic, drawing, and UI (SwiftUI)
build.sh               Builds Drinking Bird.app and its icon
cmd-enter-claude.sh    The original shell script this app replaces
```

## How it works

A timer fires at the chosen interval. If the frontmost app's name matches the **App** setting and the app has Accessibility permission, it posts a Return key press (key code 36), with the Command modifier when `⌘ + Enter` is selected, and starts the dip animation.
