# Sotto for Linux

Direction A of the [design gallery](https://plans.kristofferr.com/d/fo12u4el8h2x), implemented in Qt Quick. The familiar five-page sidebar, shared preferences and compact dictation capsule stay consistent across themes.

## Build and run

Requires CMake 3.24+, a C++20 compiler, Qt 6.8+ (Quick, QuickControls2, Widgets, Network, Svg; Test for the default test build), and the existing Bun Linux client toolchain. On Arch these Qt modules are provided by qt6-base, qt6-declarative and qt6-svg.

From the repository root:

```sh
bash scripts/build-linux-client.sh
bash scripts/build-linux-gui.sh
build/linux-gui/sotto-gui --preview
```

Preview mode uses bundled sample data. It never connects to the client, opens a microphone, saves settings, or changes the desktop theme. It can copy sample text when explicitly requested.

For real use, start the **configured client built from the same checkout** (`build/linux-client/sotto daemon`, or its existing user service), then run `build/linux-gui/sotto-gui`. The window does not start a second daemon or import microphone capture code from Cotto. Client setup and desktop bindings remain in the existing Linux client integration. No credentials are sent to QML.

Closing the window leaves the separate client running. Where a system tray is available, reopen the GUI from its tray icon; otherwise launch it again. Quitting the GUI removes the live capsule but does not stop shortcut dictation. The window asks you to finish or cancel its active microphone test before closing, so closing does not abandon a recording.

Install the GUI and launcher with CMake's normal install command into an explicitly chosen prefix. This does not install/configure the client service, shortcuts or receiver permissions.

## Appearance

Choose a theme in **This computer → Appearance**:

- Follow system: selects Sotto warm light or Glacier dark using Qt's color scheme hint.
- Sotto warm light / Glacier dark: the approved Mac-like palette.
- Omarchy: reads the active `colors.toml` from `$XDG_STATE_HOME/omarchy/current/theme` (default `~/.local/state`), with compatibility for `~/.config/omarchy/current/theme`. Only literal six-digit hex color assignments are consumed. Missing or unsupported palettes fall back to Glacier with a visible explanation. Background, foreground and accent drive semantic colors, with contrast correction for unreadable foregrounds/accents. A palette change is picked up within three seconds.

The theme selection is local to the GUI. Reading Omarchy colors does not write theme files, install hooks or require Omarchy on other distributions. It uses the same layout and controls as the Sotto themes.

## Implemented behavior

- Structured, versioned private Unix-socket snapshots of activity, source, trigger, last text, delivery and destination selection. The CLI command protocol remains compatible.
- Microphone tests use the existing capture controller and source fallback but **never capture a text destination, insert text or automatically select a pairing-button destination**. Test results remain available in Sotto and shared server history.
- Current transcript recovery distinguishes inserted, ready to copy and uncertain insertion. No automatic clipboard action or insertion retry.
- Shared paginated history with transcript selection/copy. Shared recognition, language, vocabulary, audio retention and text cleanup settings use the existing server revision check and preserve dictionary lists and other preferences.
- This computer's automatic priority list, system-default and fixed-input preferences persist atomically. Changes are rejected during active dictation or if configuration changed externally.
- Explicit pairing-button destination selection and release.
- The passive capsule reports preparing, recording, processing and completion/failure without continuous animation. Qt flags prohibit focus and input. It shows only when the main window is not active; successful/failed completion lingers briefly. No fake waveform or partial transcript is displayed when the controller does not supply one.

## Current boundaries

The presentation is distro-neutral. Actual recording/shortcuts/guarded insertion still depend on the existing Omarchy/Hyprland client adapter; portal adapters for other desktops are separate work. Wayland compositors control final placement and stacking of ordinary tool windows, so the capsule is not yet a cross-compositor layer-shell implementation.

Server credentials, initial setup, shortcut editing and autostart setup still use existing client configuration. Named microphone profiles, a full dictionary-list editor, audio playback, history deletion and per-page unsaved-edit recovery are not yet in this first GUI implementation. No desktop deployment or new physical receiver trial was performed for this change.

## Automated checks

```sh
bun run --cwd LinuxClient test
bun run check
ctest --test-dir build/linux-gui --output-on-failure
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  build/linux-gui/sotto-gui --preview --theme dark --capture .local/gui/dark
```

`--capture` is limited to preview mode. It renders all five pages into PNGs and exits. Qt tests check socket snapshots/disconnection, palette changes/fallback, page rendering without QML warnings, and non-activating overlay flags. Controller tests check that GUI tests cannot insert or select a destination. These checks do not claim live compositor placement or RF-range acceptance.
