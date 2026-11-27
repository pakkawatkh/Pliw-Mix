# Pliw Mix

Native macOS 14.2+ Menu Bar per-app audio mixer powered by Apple's **Core Audio Process Taps** — no virtual audio driver required.

## Features
- **Per-App Volume (0%–100%) & Mute** without changing macOS master volume
- **Per-App Output Device Routing** (e.g., send Chrome to speakers while routing a game to headphones simultaneously)
- **Clean App Filtering + Manual `+ Add App`** showing only active user applications by default, with a `+ Add App` picker to manually add idle apps or hidden audio processes
- **Automatic Helper Grouping** merges Chrome, Brave, Safari (WebKit), and Electron helper processes under their main application icon
- **Master Volume, Default Output Switcher, Persistent Per-App Settings & Launch at Login**

## Build & Test
```bash
cd Pliw-Mix
swift test
./scripts/build_app.sh
./scripts/run.sh
```
