# Sotto for Linux

Direction A of the [design gallery](https://plans.kristofferr.com/d/fo12u4el8h2x), implemented in Qt Quick. The familiar five-page sidebar, shared preferences and compact dictation capsule stay consistent across themes.

## Build and run

Requires CMake 3.24+, a C++20 compiler, Qt 6.8+ (Quick, QuickControls2, Widgets, Network, Svg, DBus; Test for the default test build), LayerShellQt 6.6+, and the existing Bun Linux client toolchain. The default test build also needs dbus-run-session. On Arch these dependencies are provided by qt6-base, qt6-declarative, qt6-svg and layer-shell-qt.

From the repository root:

```sh
bash scripts/build-linux-client.sh
bash scripts/build-linux-gui.sh
build/linux-gui/sotto-gui --preview
```

Preview mode uses bundled sample data. It never connects to the client, opens a microphone, saves settings, or changes the desktop theme. It can copy sample text when explicitly requested.

For real use, start the **configured client built from the same checkout** (`build/linux-client/sotto daemon`, or its existing user service), then run `build/linux-gui/sotto-gui`. The window does not start a second daemon or import microphone capture code from Cotto. Client setup and desktop bindings remain in the existing Linux client integration. No credentials are sent to QML.

Closing settings keeps the live capsule available, including on desktops without a system tray. Open Sotto from the application launcher or tray to return to the same window. A session-bus service permits only one live GUI per user session; sample-data previews remain independent. A missing or unresponsive session bus produces a launch error rather than starting a duplicate.

**This computer → Launch at login** writes Sotto’s own XDG autostart entry and starts the GUI with `--background`, without opening settings. Run the installed copy when enabling it, so startup uses a durable executable path. Disabling writes a hidden entry; it does not stop the current GUI or the separate dictation service. Existing entries managed outside Sotto are preserved, and save failures appear beside the switch. Preview mode cannot change startup.

**This computer → Quit Sotto feedback** (also in the optional tray menu) exits the GUI and removes the live capsule. Shortcut and pairing-button dictation remain with the separate client. The window still asks you to finish or cancel an active microphone test before closing or quitting.

Install the GUI and launcher with CMake's normal install command into an explicitly chosen prefix. This does not install/configure the client service, shortcuts or receiver permissions. Login startup only starts the GUI; the client service must already be configured to start with the desktop session.

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
- **This computer → DJI receiver on server** enables or disables pairing-button reception immediately and saves it for next login. Disabling retires this client's registration; enabling never selects it automatically. Destination controls reject changes during dictation and only release this computer's selection.
- **Check receiver** reads the server's current receiver/link and pairing-button status without recording or selecting a destination, even with reception disabled. Setup help distinguishes receiver USB access from pairing-button interface access. A connected link does not establish RF audio quality or mute state. Keyboard dictation retains fallback; pairing-button dictation pins the server receiver.
- The passive capsule reports preparing, recording, processing and completion/failure without continuous animation. On Wayland with layer-shell support, the capsule is a bottom-centred overlay on the active monitor, 80 logical pixels above the bottom edge. It reserves no workspace space, stays outside the tiling layout/task switcher, and accepts neither keyboard focus nor pointer input. Only the capsule uses layer-shell; settings remain an ordinary window. It shows only when the main window is not active; successful/failed completion lingers briefly. No fake waveform or partial transcript is displayed when the controller does not supply one.

## Current boundaries

The presentation is distro-neutral. Actual recording/shortcuts/guarded insertion still depend on the existing Omarchy/Hyprland client adapter; portal adapters for other desktops are separate work. The overlay requires a Wayland compositor implementing wlr-layer-shell (verified on Hyprland). Desktops without that protocol need a separate overlay adapter; exact placement is not guaranteed there. X11 uses passive tool-window flags and screen-relative positioning.

Server credentials, initial setup, shortcut editing and background-client service setup still use existing client configuration. Named microphone profiles, a full dictionary-list editor, audio playback, history deletion and per-page unsaved-edit recovery are not yet in this first GUI implementation. The GUI is deployed on the Omarchy desktop; overlay verification uses synthetic state without opening a microphone.

## Automated checks

```sh
bun run --cwd LinuxClient test
bun run check
ctest --test-dir build/linux-gui --output-on-failure
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  build/linux-gui/sotto-gui --preview --theme dark --capture .local/gui/dark
```

`--capture` is limited to preview mode. It renders all five pages into PNGs and exits. Qt tests check socket snapshots/disconnection, palette changes/fallback, page rendering without QML warnings, and non-activating overlay flags. Desktop tests use an isolated D-Bus session to verify background startup, duplicate-launch forwarding, missing-bus errors, autostart persistence, preview isolation and write failures. GUI tests retain the microphone-test close guard. Controller tests check that GUI tests cannot insert or select a destination. The opt-in Wayland test below shows the actual capsule twice with synthetic state, without connecting to the client or using a microphone. During the test, inspect `hyprctl -j layers` for `sotto-dictation` on layer 3, absence from `hyprctl -j clients`, unchanged tile geometry and unchanged keyboard focus. This does not test RF range.

```sh
SOTTO_GUI_TEST_WAYLAND=1 QT_QPA_PLATFORM=wayland \
  build/linux-gui/sotto-gui-tests waylandOverlayLifecycle
```
