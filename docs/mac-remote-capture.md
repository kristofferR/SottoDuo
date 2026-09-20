# Remote microphones in the Mac client

Ref [#7](https://github.com/kristofferR/sottoniox/issues/7). The Mac can control the server's [PipeWire capture provider](pipewire-capture.md) while retaining its existing microphone profiles and local Core Audio capture. Both paths use the same server processing, continuation, history and guarded text delivery.

## Everyday setup

With a capture-enabled server, open **Microphone** on the Mac and add the DJI entry labelled with the capture host to your priority list. Order it alongside your preferred Mac inputs and built-in microphone. Choose **Automatic · priority list** to use that order. Fixed selection still prefers one input and falls back to the Mac system input; **System default** always means the Mac's own input. Discovery never changes the saved order or opts into a remote microphone automatically.

Hold the shortcut on the computer where the text should go. The current take shows its chosen source; the destination is this Mac. Release to finish or cancel normally. Test microphone uses the same source selection and processing but does not paste or copy. The microphone's button and cross-computer destination arming remain in [#9](https://github.com/kristofferR/sottoniox/issues/9); this change does not send a speculative arming command.

A remote take requires no Mac audio device or local microphone permission. Accessibility and shortcut permissions still govern text insertion and the keyboard shortcut. If fallback chooses a Mac input without microphone permission, Sotto explains how to enable it. Local fallback still needs the transcription server online.

Direct DJI Bluetooth, when exposed as a working Core Audio input, remains a separate local source with a Bluetooth label. It can occupy any place in the list. Sotto does not pair, connect, reset or switch the DJI's radio mode. Prior hardware testing demonstrated usable Mac Bluetooth audio in the living room, but automatic receiver/Bluetooth handoff and coexistence are not established.

## Selection and lifecycle

Saved local UID/name/transport JSON remains valid. Remote entries additionally carry `remote: {server, hostID}`; identity includes endpoint, host and source ID, independently of names and transport labels. Equal local/remote IDs or IDs on different hosts cannot collide. Disconnected favorites and per-Mac profiles retain their positions. Changing server endpoint does not move an old remote preference to a different server.

Discovery polls cached metadata approximately once per second and refreshes before activation. It never opens audio. Remote eligibility requires presence, available capture, connected/not-applicable link, no known degraded audio, and an observation no older than 3.5 seconds and not in the future. Unknown transmitter state is unavailable; unknown audio health is allowed. A legacy server returning 404 for discovery keeps local upload support.

Activation has a three-second budget. A definitive pre-ready remote rejection can select one other eligible source within that original budget, with a new request ID and owner secret. Timeout or uncertain admission is not retried on another source. Releasing/cancelling while starting cannot turn a late response into recording or delivery. If an interrupted start response has not supplied a generation ID, no lease is renewed and the server releases the reservation within its five-second lease.

After acknowledged readiness, the source, connection, owner and destination stay pinned. The client renews its lease once per second through capture/drain, receives levels and recognition previews over NDJSON, and stops renewing after seal. One transient heartbeat network failure receives a single immediate retry within the lease; explicit server rejections are final. Remote takes automatically stop 174 seconds after the start request, reserving six seconds for stop/drain before the server’s 180-second admission deadline. The countdown uses this earlier limit. Known source loss, heartbeat failure, event-stream loss, destination sleep/lock and cancel invalidate the live take. Recovery never resumes it or pastes a result from shared history. The next activation resolves preferences again. Existing focus, protected-field, clipboard ownership and continuation checks also apply to remote takes.

A USB receiver reporting connected is not a guarantee of intelligible audio. The actual DJI remained connected during confirmed living-room audio gaps around 21–30 seconds in the earlier range test. Silence is not a reliable disconnect signal. This client cannot promise automatic fallback for those undetectable RF gaps and never splices another microphone into a sentence. The receiver-placement comparison was explicitly skipped by Kris.

## Validation

Pure API/resolver tests cover readiness, freshness, legacy configuration, endpoint/host collisions, remote-only selection, fixed/system-default fallback and recovery. Mac store tests cover persistence and independent local/remote inventories. Request tests cover owner-secret isolation and source-error classification.

`Server/tests/fixtures/capture-client-server.ts` runs an isolated synthetic provider and fake recognition backend on Linux. Set `SOTTO_CAPTURE_LONG_TEST=1` on the Mac to additionally exercise the actual three-minute admission deadline. Set `SOTTO_TEST_HOST` to a reachable tailnet IP, then set `SOTTO_CAPTURE_TEST_URL` to its printed URL when running `swift test --filter RemoteCaptureTests` on the Mac. It verifies the actual native controller and HTTP/event stack: no local device/permission, previews/meters, renewal past five seconds and through drain, a fresh admission after a definite source rejection, actionable permission fallback, source/event loss, and release/cancel during startup and recording. No hardware or real speech quality is tested by this fixture.

Physical sofa dictation with the newly built client, actual receiver power/replug and range transitions, Mac sleep/wake/lock with the remote source, and Bluetooth handoff repeatability remain end-to-end checks under [#11](https://github.com/kristofferR/sottoniox/issues/11). Installing these builds and enabling the provider on the daily server are separate deployment steps.
