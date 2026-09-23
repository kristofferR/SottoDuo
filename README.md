# SottoDuo

Hold a key, speak, and release to insert your dictation. SottoDuo is a native Swift macOS app backed by a Bun-compiled TypeScript/Fastify model server running on the same Mac, another Mac, or Linux. Audio uploads while you speak; the server returns progress and one finished transcript.

The dev runner builds **SottoDuo Dev**, with separate settings and visible Dev labels. For the regular app, run `./scripts/build-app.sh` and install `build/SottoDuo.app` in Applications. Both connect to an independently running server.

Upgrading the regular Mac app from Sotto installs a new app identity. In **System Settings → Privacy & Security**, grant SottoDuo Microphone and Accessibility access again, plus Input Monitoring if you use the DJI mic button. Under **General → Login Items**, remove the old app's login entry and enable **Start SottoDuo at login** in SottoDuo if you want it to start automatically. The old permissions and login entry do not transfer to the new bundle ID.

## Get started on one Mac

You need Apple Silicon, macOS 14+, full Xcode 26+ with the Metal compiler, Bun 1.4.2, CMake, and Git. Xcode provides Swift; the client/MLX build requires Swift 6.2+. Python 3 is only needed for the test scripts. Bun manages JavaScript dependencies and builds standalone server executables.

```sh
git clone --recurse-submodules https://github.com/kristofferR/sottoduo.git
cd sottoduo
```

[Download the pinned Whisper and Qwen models](Server/README.md#models) into `.local/models`, then build and start:

```sh
export SOTTODUO_SPEECH_MODEL="$PWD/.local/models/ggml-large-v3-turbo.bin"
export SOTTODUO_TEXT_MODEL="$PWD/.local/models/Qwen3-4B-Instruct-2507-MLX-4bit"
./scripts/run-dev.sh
```

Use your own model paths if they are already installed. The script builds the server and client, starts **http://localhost:8391**, and opens `build/SottoDuo Dev.app`. The first build fetches dependencies and the small Silero speech detector.

1. Grant **SottoDuo Dev** Microphone and Accessibility permissions.
2. Wait for the server to be ready. Focus a text field, hold **Right Option**, speak, and release.
3. Change the shortcut under **This Mac**, choose inputs under **Microphone**, and edit shared cleanup instructions or dictionary entries under **Server preferences**.

**Test microphone** shows a result in SottoDuo without inserting it. Fn/Globe is also supported; set macOS **Keyboard → Press Globe key to → Do Nothing** if its system action conflicts.

## DJI mic button

Connect a DJI Mic Mini, Mini 2, or Mini 2S receiver over USB-C. The **This Mac → DJI mic button** settings appear after SottoDuo first detects a DJI microphone and stay visible afterward, including across app restarts. Enable **Use DJI mic button** and allow Input Monitoring when requested. Press the transmitter's linking button once to start dictation, then again to stop and insert. Escape cancels. SottoDuo uses the input selected under **Microphone**; choose the DJI receiver there to record from it.

The button uses the receiver's USB consumer-control interface (`2CA3:4011`), as documented by [dji-mic-wispr-flow](https://github.com/caezium/dji-mic-wispr-flow). Bluetooth-only connections do not send these events. SottoDuo handles the receiver directly without Karabiner; disable other DJI button mappings first. While enabled, SottoDuo captures the receiver's consumer controls so its button does not change system volume. Keyboard volume keys remain available. Disabling the feature or quitting releases the receiver.

Repeated button events are ignored. Presses during transcription, keyboard dictation, or a microphone test do not start another take. Unplugging the receiver cancels its active recording; sleep and locking the Mac interrupt recording too. **Check receiver** retries capture after changing permissions or disabling another mapping tool.

## Use a server on another machine

Follow the [server guide](Server/README.md) for macOS, Linux, or containers. On the client Mac, build and open only the app:

```sh
./scripts/build-app.sh
open "build/SottoDuo.app"
```

Set its URL and token under **This Mac**. Use HTTPS for remote hosts, or HTTP with the server's literal Tailscale IP on your connected tailnet. The client needs no model weights or GPU for inference.

## Daily development

```sh
./scripts/run-dev.sh start --skip-build   # Start existing builds
./scripts/run-dev.sh status
./scripts/run-dev.sh stop
./scripts/run-dev.sh restart             # Rebuild and restart the server
swift test
./scripts/smoke-test.sh                  # Real HTTP/audio test; server must be idle
./scripts/test-corrections.sh            # Real Qwen helper checks
```

Keep the model-path exports set when starting the server or running helper checks. After rebuilding an already-open client, quit and reopen it to load the new executable. Release builds prefer a unique Developer ID Application identity, then an Apple Development identity, with ad-hoc signing as the fallback. Set `SOTTODUO_SIGNING_IDENTITY` to select a certificate explicitly. Ad-hoc rebuilds may require granting permissions again.

The dev runner stores shared history/settings in `.local/server`, device preferences in `.local/client`, and logs in `.local/server.log`. Keep experiment notes and generated artifacts under the ignored `.local/` directory too. Quitting the app leaves the server running. Recordings require an online, available server and have a three-minute limit.

For newly launched Electron apps, SottoDuo requests accessibility support when a take begins and checks for an editable field for up to three seconds while recording starts independently. The field must become verifiable before you release the key; a short first take or slow renderer can still use the clipboard fallback. Unsupported native apps do not wait for this preparation. Enabling an Electron accessibility tree can increase that app's memory and CPU use for its lifetime; SottoDuo leaves it enabled so other assistive tools can continue using it. This activation mechanism is specific to Electron; Chrome fields use their existing accessibility support.

All connected Macs share history, tagged by device. Both original and inference audio are kept by default; **Keep original microphone audio** changes original retention for future takes. Back up the server data directory to preserve history.

## Reference

- [Server setup and models](Server/README.md)
- [Architecture, configuration, and storage](docs/architecture.md)
- [Dictionary and cleanup instructions](docs/text-correction.md)
- [HTTP API](docs/client-server-contract.md)
- [Whisper helper](Engine/README.md) and [Qwen helpers](TextEngine/README.md)

[MIT](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
