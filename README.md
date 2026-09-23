<p align="center">
  <img src="LinuxClient/gui/mark.svg" width="128" height="128" alt="SottoDuo app icon">
</p>

<h1 align="center">SottoDuo</h1>

<p align="center">
  <strong>Hold a key. Speak. Keep writing.</strong><br>
  Open-source dictation for macOS and Linux, with local or cloud speech recognition.
</p>

<p align="center">
  <a href="https://github.com/kristofferR/SottoDuo/actions/workflows/server.yml"><img src="https://github.com/kristofferR/SottoDuo/actions/workflows/server.yml/badge.svg" alt="Build and test status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/kristofferR/SottoDuo?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#get-started">Get started</a> ·
  <a href="#changes-from-upstream-sotto">Changes from upstream Sotto</a> ·
  <a href="#documentation">Documentation</a>
</p>

---

SottoDuo turns speech into text in the app you're using. Hold your dictation
shortcut, speak, and release to insert the result. Use a microphone on your
computer, or share one connected to a Linux server between your Mac and Linux
desktop. A DJI transmitter button can start and stop dictation without touching
the keyboard.

The desktop apps connect to a server you run on your own hardware. It handles
speech recognition, optional text cleanup, and shared history. Run everything
on one Mac, or let a separate machine do the inference for your computers.

## Why SottoDuo?

- **Dictate where you work.** A global shortcut and compact recording overlay
  keep you in your current app. Unsupported text fields have a copy fallback.
- **Choose local or cloud recognition.** Use Whisper on your own hardware,
  Soniox streaming, or automatic cloud-to-local fallback.
- **Share a microphone across computers.** Keep a USB receiver plugged into
  your Linux machine and dictate into either desktop.
- **Use the mic's button.** Tap a supported DJI transmitter's linking button
  to start, then tap again to finish.
- **Keep your words consistent.** Shared dictionaries, preferred spellings,
  recognition vocabulary, and optional Qwen proofreading.
- **Find previous dictations.** Shared history includes transcripts, retained
  audio, and the device that recorded each take.

## Changes from upstream Sotto

SottoDuo is a fork of [Sotto by davis7dotsh](https://github.com/davis7dotsh/sotto).
Upstream provides the native Mac app, self-hosted Whisper/Qwen pipeline,
Mac/Linux server, dictionaries, shared history, and Wispr Flow history import.
This fork builds on that foundation:

| Addition | What it does |
| --- | --- |
| **Linux desktop app** | A native Qt Quick interface with dictation, history, microphone priorities, shared server preferences, and a floating recording capsule. Desktop integration targets Omarchy/Hyprland and KDE Plasma Wayland. |
| **Soniox streaming** | Cloud speech recognition with live transcript previews, Automatic / Cloud only / Local only modes, and full-recording Whisper fallback when cloud recognition fails in Automatic mode. |
| **Remote microphones** | On-demand PipeWire capture on a Linux server. The Mac can select remote inputs alongside its own microphones; the Linux client records through the capture server. |
| **DJI button dictation** | USB receiver button support on the Mac and Linux server, plus routing to a selected Mac or Linux destination. |
| **Linux appearance and desktop controls** | Light and dark themes, an Omarchy theme option, shortcut setup, background service controls, and launch at login. |
| **SottoDuo identity** | A separate app name and icon, with migration support for settings and data from earlier fork builds. |

The server and text-cleanup pipeline remain shared across platforms. Linux
insertion depends on application accessibility support; terminals use explicit
copy and paste. Omarchy/Hyprland is the verified Linux desktop; Plasma integration
still needs real-device validation, and its overlay placement is not guaranteed.
Wispr Flow history import runs on the Mac, while either desktop can browse
imported records.

## Recognition and privacy

| Mode | How speech is recognized |
| --- | --- |
| **Automatic** | Uses Soniox when a server API key is configured, otherwise Whisper. A cloud failure falls back to Whisper using the complete recording. Requires local Whisper to be ready. |
| **Cloud only** | Uses Soniox. Can accept recordings without local speech models; cloud failures are reported without local fallback. |
| **Local only** | Uses Whisper on your server. No audio is sent to Soniox. |

Choose the mode under **Server preferences**. Soniox requires your own API key;
configure it on the server using `SONIOX_API_KEY` or `--soniox-key-file`.
Cloud recognition sends normalized speech audio and vocabulary hints to Soniox.
Optional Qwen proofreading runs on your own server in every mode.

History and retained recordings live in the server's data directory. Original
microphone audio is kept by default; **Keep original microphone audio** controls
its retention for future takes. Back up that directory to preserve your history.
The desktop apps always need a reachable server, including in Local only mode.

See [Soniox setup and fallback behavior](docs/soniox-streaming.md) and
[server storage](docs/architecture.md#storage).

## Get started

SottoDuo currently requires a source build. There are no published app installers.
Choose a desktop client and a server:

| Component | Requirements |
| --- | --- |
| **Mac app and local server** | Apple Silicon, macOS 14+, Xcode 26+ with the Metal compiler, Swift 6.2+, Bun 1.4.2, CMake, and Git. |
| **Linux desktop** | Omarchy/Hyprland or experimental KDE Plasma Wayland, the Linux client dependencies, Qt 6.8+, and LayerShellQt 6.6+. Requires a server with PipeWire capture enabled. |
| **Separate server** | Apple Silicon macOS, or Linux x86_64/ARM64 with CPU or optional NVIDIA CUDA inference. Linux container builds are also available. |

### On one Mac

```sh
git clone --recurse-submodules https://github.com/kristofferR/SottoDuo.git
cd SottoDuo
```

[Download the Whisper and Qwen models](Server/README.md#models) into `.local/models`,
then build and start:

```sh
export SOTTODUO_SPEECH_MODEL="$PWD/.local/models/ggml-large-v3-turbo.bin"
export SOTTODUO_TEXT_MODEL="$PWD/.local/models/Qwen3-4B-Instruct-2507-MLX-4bit"
./scripts/run-dev.sh
```

This starts the server at **http://localhost:8391** and opens **SottoDuo Dev**,
which has separate settings from the regular app.

1. Grant **Microphone** and **Accessibility** permissions when requested.
2. Wait for the server to be ready, focus a text field, hold <kbd>Right Option</kbd>,
   speak, and release.
3. Choose your shortcut under **This Mac**, inputs under **Microphone**, and
   dictionary or cleanup settings under **Server preferences**.

**Test microphone** lets you check a recording without inserting text.
Recordings have a three-minute limit. Fn/Globe shortcuts are also supported;
set macOS **Keyboard → Press Globe key to → Do Nothing** if its action conflicts.

For the regular app, run `./scripts/build-app.sh` and move `build/SottoDuo.app`
to Applications. It still needs the independently running server.

### On Linux

Start with the [Linux desktop guide](LinuxClient/gui/README.md) for dependencies
and installation, and enable [PipeWire capture](docs/pipewire-capture.md) on the
server. From a cloned repository with those dependencies installed:

```sh
bun install --frozen-lockfile
bash scripts/build-linux-client.sh
bash scripts/build-linux-gui.sh
build/linux-gui/sottoduo-gui
```

Under **This computer**, set up **Background dictation**, enter your server
details under **Connection**, and configure **Shortcuts**. Choose your inputs
under **Microphone**. The server's capture provider handles Linux recording,
including when the client and server run on the same computer.

### With a separate server

Follow the [server guide](Server/README.md) to build, install models, and run on
macOS, Linux, or in a container. On a client Mac, build only the app with
`./scripts/build-app.sh`; it needs no inference models locally.

Enter the server URL and token under **This Mac** or Linux's
**This computer → Connection**. Use HTTPS for remote hosts, or HTTP with the
server's literal Tailscale IP on your connected tailnet. Ordinary LAN addresses
require HTTPS.

## DJI microphone button

Supported USB receivers include DJI Mic Mini, Mini 2, and Mini 2S using the
`2CA3:4011` consumer-control interface. Connect the receiver over USB, then tap
the transmitter's linking button once to record and again to finish.
Bluetooth-only connections do not provide these button events.

- **Receiver on your Mac:** Enable **This Mac → DJI mic button → Use DJI mic
  button**, allow Input Monitoring, and select the receiver under **Microphone**.
- **Receiver on the Linux server:** Configure the capture and button helpers,
  enable reception on each client, and select the destination computer. A
  successful keyboard dictation can also select that computer for the next
  button take.

The destination stays fixed throughout a recording. Server-button selection
clears when the selected client locks, sleeps, or disconnects. Microphone
priorities apply to new recordings; SottoDuo does not switch inputs mid-sentence
or automatically hand off between USB and Bluetooth.

See [DJI button routing and setup](docs/dji-button-routing.md) and
[remote microphone selection on Mac](docs/mac-remote-capture.md).
USB button support builds on the findings in
[dji-mic-wispr-flow](https://github.com/caezium/dji-mic-wispr-flow).

## Development

```sh
./scripts/run-dev.sh start --skip-build   # Start existing Mac development builds
./scripts/run-dev.sh status
./scripts/run-dev.sh stop
./scripts/run-dev.sh restart             # Rebuild and restart
bun run check
bun run test
swift test                              # Swift client and shared code
```

Keep the model-path exports set for the Mac dev runner. It stores server data
in `.local/server`, client preferences in `.local/client`, and logs in
`.local/server.log`. Quitting the app leaves the server running. After rebuilding
an open client, quit and reopen it to load the new executable.

For HTTP/audio smoke tests, native helper checks, and Linux GUI tests, see the
[server](Server/README.md#verify) and
[Linux desktop](LinuxClient/gui/README.md#automated-checks) guides.

## Documentation

- [Server setup, models, containers, and remote access](Server/README.md)
- [Linux desktop setup and features](LinuxClient/gui/README.md)
- [Soniox streaming and local fallback](docs/soniox-streaming.md)
- [PipeWire microphone capture](docs/pipewire-capture.md)
- [DJI button routing](docs/dji-button-routing.md)
- [Dictionary and cleanup instructions](docs/text-correction.md)
- [Architecture and storage](docs/architecture.md)
- [HTTP API](docs/client-server-contract.md)
- [Whisper helper](Engine/README.md) and [Qwen helpers](TextEngine/README.md)

## Support and contributing

[Open an issue](https://github.com/kristofferR/SottoDuo/issues) for bugs or ideas.
For a dictation problem, include your desktop environment, server platform,
recognition mode, and microphone setup. Keep API keys, access tokens, and private
recordings out of reports.

Contributions are welcome; see [repository instructions](AGENTS.md) for the
contributor PR requirements.

## License and credits

[MIT](LICENSE). Forked from [Sotto](https://github.com/davis7dotsh/sotto) by
davis7dotsh. See [third-party notices](THIRD_PARTY_NOTICES.md) for bundled
dependencies and model licenses.
