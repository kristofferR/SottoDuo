import type { CaptureHandle, CaptureProvider } from "../capture-sessions.ts";
import type { AudioKind, AudioStreamFormat } from "../api.ts";
import type { PipeWireInput } from "./pipewire-discovery.ts";
import { captureHelper } from "./helper.ts";

type Options = Parameters<CaptureProvider["start"]>[0];
interface AudioStream {
  kind: AudioKind;
  format: AudioStreamFormat;
  bytes: Buffer;
  frames: number;
  sequence: number;
}
export function recordPipeWire(helper: string, input: PipeWireInput, options: Options) {
  const format = input.format!;
  const retain = options.generation.settings.preferences.keepOriginalAudio;
  const process = captureHelper(helper, [
    "capture",
    input.serial,
    String(format.sampleRate),
    String(format.channels),
    retain ? "1" : "0",
  ]);
  const inference: AudioStream = {
    kind: "inference",
    format: { sampleRate: 16000, channels: 1 },
    bytes: Buffer.alloc(0),
    frames: 0,
    sequence: 0,
  };
  const original: AudioStream = {
    kind: "original",
    format,
    bytes: Buffer.alloc(0),
    frames: 0,
    sequence: 0,
  };
  let pending = Buffer.alloc(0),
    queuedBytes = 0,
    queue = Promise.resolve();
  let ready = false,
    ended = false,
    stopping = false,
    failed = false;
  const preparation = Promise.withResolvers<CaptureHandle>();
  // Attach immediately, even if the provider caller is cancelled before it awaits readiness.
  void preparation.promise.catch(() => {});
  const failure = () => {
    if (failed) return;
    failed = true;
    pending = Buffer.alloc(0);
    inference.bytes = original.bytes = Buffer.alloc(0);
    preparation.reject(new Error("PipeWire capture failed."));
    void process.kill();
    options.lost();
  };
  const abort = () => {
    failed = true;
    preparation.reject(new Error("PipeWire capture aborted."));
    void process.kill();
  };
  options.signal.addEventListener("abort", abort, { once: true });
  if (options.signal.aborted) abort();
  const write = (stream: AudioStream, bytes: Buffer) => {
    queuedBytes += bytes.length;
    if (queuedBytes > 2_097_152) {
      failure();
      return;
    }
    const sequence = stream.sequence++;
    stream.frames += bytes.length / (4 * stream.format.channels);
    queue = queue
      .then(async () => {
        if (!failed) await options.write(stream.kind, sequence, stream.format, bytes);
      })
      .catch(failure)
      .finally(() => {
        queuedBytes -= bytes.length;
      });
  };
  const append = (stream: typeof inference, bytes: Buffer) => {
    if (bytes.length % (stream.format.channels * 4)) throw new Error("Partial PCM frame.");
    for (let i = 0; i < bytes.length; i += 4)
      if (!Number.isFinite(bytes.readFloatLE(i))) throw new Error("Invalid PCM.");
    stream.bytes = Buffer.concat([stream.bytes, bytes]);
    const chunk = Math.floor(stream.format.sampleRate / 10) * stream.format.channels * 4;
    while (stream.bytes.length >= chunk && !failed) {
      const bytes = Buffer.from(stream.bytes.subarray(0, chunk));
      stream.bytes = stream.bytes.subarray(chunk);
      if (stream === inference) {
        let peak = 0;
        for (let i = 0; i < bytes.length; i += 4)
          peak = Math.max(peak, Math.abs(bytes.readFloatLE(i)));
        options.level(Math.min(1, peak));
      }
      write(stream, bytes);
    }
  };
  let stopped: Promise<Awaited<ReturnType<CaptureHandle["stop"]>>> | undefined;
  const handle: CaptureHandle = {
    stop: () =>
      (stopped ??= (async () => {
        if (failed || !ready) throw new Error("Capture is not active.");
        stopping = true;
        process.child.stdin.end("s");
        const exit = await process.completion;
        if (exit !== 0 || failed || !ended || pending.length)
          throw new Error("Incomplete capture.");
        for (const stream of retain ? [inference, original] : [inference]) {
          if (stream.bytes.length) {
            write(stream, stream.bytes);
            stream.bytes = Buffer.alloc(0);
          }
        }
        await queue;
        if (failed) throw new Error("Audio could not be retained.");
        return {
          inferenceFrames: inference.frames,
          ...(retain ? { originalFrames: original.frames } : {}),
        };
      })()),
  };
  process.child.stdout.on("data", (bytes: Buffer) => {
    if (failed) return;
    try {
      if (bytes.length > 1_048_576) throw new Error("Capture output overflow.");
      pending = Buffer.concat([pending, bytes]);
      while (pending.length >= 8 && !failed) {
        const type = pending.readUInt32LE(0),
          length = pending.readUInt32LE(4);
        if (length > 262_144 || ended || type < 1 || type > 4)
          throw new Error("Invalid capture packet.");
        if (pending.length < length + 8) break;
        const payload = pending.subarray(8, length + 8);
        pending = pending.subarray(length + 8);
        if (type === 3) {
          if (ready || length) throw new Error("Duplicate readiness.");
          ready = true;
          preparation.resolve(handle);
        } else if (!ready) throw new Error("Audio before readiness.");
        else if (type === 4) {
          if (!stopping || length) throw new Error("Unexpected capture end.");
          ended = true;
        } else if (!length || (type === 1 && !retain)) throw new Error("Unexpected PCM.");
        else append(type === 1 ? original : inference, payload);
      }
    } catch {
      failure();
    }
  });
  void process.completion.then((code) => {
    if (!stopping || code !== 0 || !ended) failure();
  });
  return {
    ready: preparation.promise,
    done: process.completion,
    cancel: process.kill,
    cleanup: () => options.signal.removeEventListener("abort", abort),
  };
}
