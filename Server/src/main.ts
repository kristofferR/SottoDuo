import { acquireDataDirectoryLock } from "./data-lock.ts";
import { parseConfiguration, usage, type ServerConfiguration } from "./configuration.ts";
import { createHTTPServer } from "./http-server.ts";
import { GenerationService, defaultProofreadingPrompt } from "./generation-service.ts";
import { NativeInference, type InferenceBackend } from "./inference/native-inference.ts";
import { PipeWireCaptureProvider } from "./capture/pipewire-provider.ts";

export async function startServer(configuration: ServerConfiguration, backend?: InferenceBackend) {
  if (configuration.button && !configuration.capture)
    throw new Error("Button routing requires a configured capture provider.");
  const lock = acquireDataDirectoryLock(configuration.dataDirectory);
  let service: GenerationService | undefined;
  let capture: PipeWireCaptureProvider | undefined;
  try {
    capture = configuration.capture
      ? await PipeWireCaptureProvider.open(configuration.capture)
      : undefined;
    service = await GenerationService.open(
      { ...configuration, captureProvider: capture },
      backend ?? new NativeInference(configuration.inference),
    );
    if (configuration.button)
      capture?.attachButtons(
        configuration.button.helper,
        configuration.button.sourceID,
        service.buttons,
      );
    const app = createHTTPServer(service, configuration.token);
    await service.start();
    const address = await app.listen({ host: configuration.host, port: configuration.port });
    let closing: Promise<void> | undefined;
    const close = () =>
      (closing ??= (async () => {
        try {
          await service!.shutdown();
        } finally {
          try {
            try {
              await capture?.close();
            } finally {
              await app.close();
            }
          } finally {
            lock.release();
          }
        }
      })());
    return { app, service, address, close };
  } catch (error) {
    try {
      try {
        await service?.shutdown();
      } finally {
        await capture?.close();
      }
    } finally {
      lock.release();
    }
    throw error;
  }
}

if (import.meta.main) {
  try {
    if (process.argv.includes("--help") || process.argv.includes("-h")) console.log(usage);
    else if (process.argv.includes("--print-default-proofreading-prompt"))
      console.log(defaultProofreadingPrompt);
    else {
      const server = await startServer(await parseConfiguration());
      console.log(`Sotto server listening at ${server.address}`);
      const stop = () => {
        void server.close().then(
          () => process.exit(0),
          () => process.exit(1),
        );
      };
      process.once("SIGTERM", stop);
      process.once("SIGINT", stop);
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : "The server could not start.");
    process.exitCode = 1;
  }
}
