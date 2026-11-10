<div align="center">

  <h1>🔊 QuickMixer</h1>

  <p><strong>Instant, zero-latency access to the Windows Volume Mixer (SndVol) with borderless flyout styling.</strong></p>

  <p>
    <img src="https://img.shields.io/badge/AutoHotkey-v2.0+-334455.svg" alt="AutoHotkey v2" />
    <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg" alt="Windows" />
    <img src="https://img.shields.io/badge/Memory-~4.8%20MB-2ea44f.svg" alt="RAM Usage" />
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" />
  </p>

  <p>
    <a href="#features">Features</a> •
    <a href="#requirements">Requirements</a> •
    <a href="#installation">Installation</a> •
    <a href="#usage">Usage</a> •
    <a href="#settings">Settings</a> •
    <a href="#building-from-source">Build</a> •
    <a href="#license">License</a>
  </p>

</div>

---

## Features

- ⚡ **Instant reveal (pre-warmed)** — silent background standby delivers true zero-latency 0ms pop-in on click or hotkey
- 🪟 **Borderless flyout styling** — strips heavy legacy window borders in Full Mixer mode for a clean, frameless flyout look that auto-dismisses when clicking outside
- 🎛️ **Dual mixer modes** — toggle between the **Full Volume Mixer** (per-app and device sliders) or classic **Master Volume** (single slider)
- 🔊 **System tray icon** — speaker icon in your notification area; click to toggle the mixer floating cleanly above the taskbar
- 🛡️ **Zero-leak Job Object cleanup** — Windows kernel-enforced child process management guarantees no orphaned `sndvol.exe` processes linger if the script exits or crashes
- ⌨️ **Global hotkey** — open or toggle the mixer at your mouse cursor from anywhere (default `Ctrl+Alt+V`)
- 📌 **No-tray headless mode** — run headlessly on demand at saved screen coordinates, then exit
- ⚙️ **In-app settings GUI** — easily configure hotkeys, modes, positions, and styling without editing config files
- 📝 **Defensive INI storage** — persistent companion `.ini` file with automatic validation and fallback defaults

---

## Requirements

- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- Windows Vista or later (requires `sndvol -f` and the modern Windows audio subsystem)

> [!NOTE]
> Windows XP and earlier are not supported. The Volume Mixer (`sndvol -f`) was introduced in Windows Vista. The legacy `sndvol32.exe` found on XP and older systems is an entirely different program and is not compatible.

---

## Installation

### Running from Script
1. Install [AutoHotkey v2](https://www.autohotkey.com/download/)
2. Clone or download this repository
3. Double-click `quickmixer.ahk` to launch

### Running from Standalone Executable
Download or compile `quickmixer.exe` using [`make.bat`](#building-from-source). No AutoHotkey installation is required to run the compiled executable.

> [!TIP]
> A `quickmixer.ini` configuration file is generated automatically alongside the script/executable on first run.

---

## Usage

### System Tray Mode (Default)
When `TrayIcon=1` (default), QuickMixer runs persistently in the notification area:

| Action | Result |
|---|---|
| **Single click** tray icon | Toggles Volume Mixer open/closed above the taskbar |
| **Double click** tray icon | Toggles Volume Mixer open/closed above the taskbar (debounced) |
| **Hotkey** (`Ctrl+Alt+V`) | Toggles Volume Mixer open/closed centered at the cursor |
| **Right-click** → **Settings** | Opens the QuickMixer Settings window |
| **Right-click** → **Exit** | Fully closes QuickMixer and terminates cached processes |

### Headless / No-Tray Mode
When `TrayIcon=0`, QuickMixer runs headlessly: it opens the Volume Mixer once at the saved `X`/`Y` fallback coordinates and exits immediately. This is ideal for invocation via third-party docks, stream decks, Task Scheduler, or CLI shortcuts.

---

## Settings

Right-click the tray icon and choose **Settings** to open the configuration dialog:

| Section | Option | Description |
|---|---|---|
| **Mixer Mode** | **Full Volume Mixer** | Opens the full mixer with all individual application and device sliders |
| | **Master Volume only** | Opens the compact single-slider master volume control |
| | **Minimal decorations** | Strips titlebar & borders for a frameless flyout that auto-closes on blur |
| | **Instant reveal** | Keeps a pre-warmed instance in background memory for 0ms pop-in |
| **Mixer Positioning** | **Show tray icon** | Toggle persistent notification area tray icon on or off |
| | **Fallback X / Y** | Screen coordinates used when launching in headless mode |
| | **⟳ Mouse** | Captures your current cursor coordinates into the fallback fields |
| **Hotkey** | **Hotkey** | Global key combination to summon the mixer (supports `^`, `!`, `+`, `#`) |

> [!NOTE]
> Changes to Minimal decorations, Instant reveal, and Mixer Mode apply live immediately upon clicking **Save**. Changes to the system tray icon require a script restart to take effect.

---

## Building from Source

A build script [`make.bat`](make.bat) is included to compile the script into a standalone `.exe`:

```cmd
:: Interactive build menu
make.bat

:: Direct CLI builds
make.bat x64    :: Builds 64-bit quickmixer.exe (Recommended)
make.bat x86    :: Builds 32-bit quickmixer.exe
make.bat all    :: Builds both architectures to bin\
make.bat gui    :: Launches Ahk2Exe GUI
```

---

## Configuration (`quickmixer.ini`)

Settings are stored in `quickmixer.ini` alongside the script or executable:

```ini
[Position]
X=1820
Y=900

[Settings]
Hotkey=^!v
TrayIcon=1
MixerMode=Full
MinimalDecorations=1
Prewarm=1
```

---

## License

Distributed under the [MIT License](LICENSE).
