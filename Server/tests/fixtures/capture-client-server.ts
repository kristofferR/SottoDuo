// Native Mac capture contract fixture. Synthetic audio only; no device or model access.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { CaptureProvider } from "../../src/capture-sessions.ts";
import { GenerationService } from "../../src/generation-service.ts";
import { createHTTPServer } from "../../src/http-server.ts";
import { FakeInference } from "../support.ts";

const directory = await mkdtemp(join(tmpdir(), "sotto-capture-client-"));
const provider: CaptureProvider = {
  sources: () =>
    [
      "ready",
      "lost",
      "slow",
      "reject",
      "unknown",
      "event-loss",
      "heartbeat-once",
      "heartbeat-loss",
    ].map((id) => ({
      identity: { hostID: "capture-fixture", id },
      name: `Fixture ${id}`,
      transport: "usb",
      present: true,
      link: id === "unknown" ? "unknown" : "connected",
      capture: "available",
      audioHealth: "unknown",
      observedAt: new Date().toISOString(),
    })),
  async start(options) {
    const id = options.generation.capture?.source.id;
    if (id === "reject") throw new Error("Fixture source failed before readiness");
    if (id === "slow") await Bun.sleep(2_000);
    options.signal.throwIfAborted();
    const levels = setInterval(() => options.level(0.25), 120);
    const lost = id === "lost" ? setTimeout(() => options.lost(), 700) : undefined;
    options.signal.addEventListener(
      "abort",
      () => {
        clearInterval(levels);
        clearTimeout(lost);
      },
      { once: true },
    );
    // Seed the normal recognition-preview path before stop as real capture does.
    await options.write("inference", 0, { sampleRate: 16_000, channels: 1 }, Buffer.alloc(64_000));
    if (options.generation.settings.preferences.keepOriginalAudio)
      await options.write(
        "original",
        0,
        { sampleRate: 48_000, channels: 1 },
        Buffer.alloc(192_000),
      );
    return {
      async stop() {
        clearInterval(levels);
        clearTimeout(lost);
        await Bun.sleep(1_400); // A heartbeat must continue through the drain.
        return {
          inferenceFrames: 16_000,
          ...(options.generation.settings.preferences.keepOriginalAudio
            ? { originalFrames: 48_000 }
            : {}),
        };
      },
    };
  },
};
const service = await GenerationService.open(
  {
    dataDirectory: directory,
    development: true,
    captureProvider: provider,
    soniox: { apiKey: "fixture", endpoint: "wss://example.invalid", model: "stt-rt-v5" },
    startSpeechStream: (_configuration, _language, _terms, _id, update) => ({
      send() {
        update("Remote preview.");
      },
      async finish() {
        return {
          text: "Remote transcript.",
          audioSeconds: 1,
          language: "en",
          processingSeconds: 0.01,
        };
      },
      cancel() {},
    }),
  },
  new FakeInference(),
);
const preferences = await service.getPreferences();
preferences.preferences.textCorrectionEnabled = false;
await service.updatePreferences(preferences);
const app = createHTTPServer(service, "sotto-native-capture-test-token-2026");
let discoveryUnavailable = false;
const droppedHeartbeats = new Set<string>();
app.post<{ Body: { unavailable: boolean } }>("/fixture/discovery", async (request, reply) => {
  discoveryUnavailable = request.body.unavailable === true;
  return reply.code(204).send();
});
app.addHook("onRequest", async (request, reply) => {
  if (request.url === "/v1/audio-sources" && discoveryUnavailable)
    return reply
      .code(503)
      .send({ code: "invalid_sources", message: "Fixture discovery unavailable" });
  const match = /^\/v1\/generations\/([^/]+)\/(events|capture\/heartbeat)$/.exec(request.url);
  if (!match) return;
  const record = await service.get(match[1]!);
  const source = record.capture?.source.id;
  if (match[2] === "capture/heartbeat") {
    if (
      source === "heartbeat-loss" ||
      (source === "heartbeat-once" && !droppedHeartbeats.has(record.id))
    ) {
      droppedHeartbeats.add(record.id);
      reply.hijack();
      reply.raw.destroy();
    }
    return;
  }
  if (record.capture?.source.id !== "event-loss") return;
  reply.hijack();
  reply.raw.writeHead(200, { "Content-Type": "application/x-ndjson" });
  reply.raw.end(JSON.stringify(record) + "\n");
});
console.log(await app.listen({ host: process.env.SOTTO_TEST_HOST ?? "127.0.0.1", port: 0 }));
for (const signal of ["SIGTERM", "SIGINT"] as const)
  process.once(signal, () => {
    void (async () => {
      await service.shutdown();
      await app.close();
      await rm(directory, { recursive: true, force: true });
      process.exit(0);
    })();
  });
