// Native-client contract fixture. Run on Omarchy; the Mac connects over Tailscale.
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GenerationService } from "../../src/generation-service.ts";
import { createHTTPServer } from "../../src/http-server.ts";
import { FakeInference } from "../support.ts";

const directory = await mkdtemp(join(tmpdir(), "sottoduo-streaming-client-"));
const service = await GenerationService.open(
  {
    dataDirectory: directory,
    development: true,
    soniox: { apiKey: "fixture", endpoint: "wss://example.invalid", model: "stt-rt-v5" },
    startSpeechStream: (_configuration, _language, _terms, _id, update, failed) => {
      let disconnected = false;
      return {
        send(bytes) {
          if (bytes.readFloatLE(0) === 0.25) {
            disconnected = true;
            failed("Fixture cloud disconnected.");
          } else update("Live cloud preview.");
        },
        async finish() {
          if (disconnected) throw new Error("Disconnected");
          return {
            text: "Cloud transcript.",
            audioSeconds: 1,
            language: "en",
            processingSeconds: 0.01,
          };
        },
        cancel() {},
      };
    },
  },
  new FakeInference(),
);
const preferences = await service.getPreferences();
preferences.preferences.textCorrectionEnabled = false;
await service.updatePreferences(preferences);
const app = createHTTPServer(service, "sottoduo-native-streaming-test-token-2026");
app.addHook("onRequest", async (request, reply) => {
  if (request.url.endsWith("/stream") && request.headers["x-sottoduo-test-block-upgrade"] === "1")
    return reply.code(426).send({ message: "Fixture proxy does not forward WebSocket upgrades." });
});
const address = await app.listen({ host: process.env.SOTTODUO_TEST_HOST ?? "127.0.0.1", port: 0 });
console.log(address);
for (const signal of ["SIGTERM", "SIGINT"] as const)
  process.once(signal, () => {
    void (async () => {
      await service.shutdown();
      await app.close();
      await rm(directory, { recursive: true, force: true });
      process.exit(0);
    })();
  });
