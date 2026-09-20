import { afterAll, beforeAll, expect, test } from "bun:test";
import { execFile, spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { randomUUID } from "node:crypto";
import { PipeWireCaptureProvider } from "../src/capture/pipewire-provider.ts";
import { GenerationService } from "../src/generation-service.ts";
import { FakeInference } from "./support.ts";

// Explicit opt-in: a private PipeWire daemon with a tone generator, never desktop audio.
const helper = process.env.SOTTO_TEST_CAPTURE_HELPER;
const nativeTest = test.skipIf(!helper || process.platform !== "linux");
const exec = promisify(execFile);
let directory: string,
  daemon: ReturnType<typeof spawn>,
  provider: PipeWireCaptureProvider,
  service: GenerationService;
let previous: { runtime?: string; remote?: string };
interface GraphObject {
  id: number;
  type: string;
  info?: { props?: Record<string, unknown> };
}
const command = async (file: string, args: string[]) =>
  (await exec(file, args, { timeout: 1500 })).stdout;
const graph = async () => JSON.parse(await command("pw-dump", [])) as GraphObject[];
async function until<T>(read: () => Promise<T | undefined>): Promise<T> {
  const end = Date.now() + 2500;
  while (Date.now() < end) {
    const value = await read();
    if (value !== undefined) return value;
    await Bun.sleep(20);
  }
  throw new Error("PipeWire condition timed out.");
}
const configure = (id: number, direction: "Input" | "Output") =>
  command("pw-cli", [
    "set-param",
    String(id),
    "PortConfig",
    `{ direction = ${direction} mode = dsp format = { mediaType = audio mediaSubtype = raw format = F32P rate = 48000 channels = 2 position = [ FL FR ] } }`,
  ]);
async function connect() {
  const node = await until(async () =>
    (await graph()).find((x) => x.info?.props?.["media.name"] === "Sotto capture"),
  );
  await configure(node.id, "Input");
  for (const channel of ["FL", "FR"])
    await command("pw-link", [
      `sotto-test-source:capture_${channel}`,
      `sotto-capture:input_${channel}`,
    ]);
}
async function noCapture() {
  await until(async () =>
    (await graph()).some((x) => x.info?.props?.["media.name"] === "Sotto capture")
      ? undefined
      : true,
  );
}
beforeAll(async () => {
  if (!helper || process.platform !== "linux") return;
  directory = await mkdtemp(join(tmpdir(), "sotto-pw-"));
  previous = { runtime: process.env.PIPEWIRE_RUNTIME_DIR, remote: process.env.PIPEWIRE_REMOTE };
  process.env.PIPEWIRE_RUNTIME_DIR = directory;
  process.env.PIPEWIRE_REMOTE = "sotto-test";
  daemon = spawn("pipewire", ["-c", resolve(import.meta.dir, "fixtures/pipewire.conf")], {
    stdio: "ignore",
  });
  const source = await until(async () => {
    try {
      return (await graph()).find((x) => x.info?.props?.["node.name"] === "sotto-test-source");
    } catch {
      return undefined;
    }
  });
  await configure(source.id, "Output");
  provider = await PipeWireCaptureProvider.open({ helper, hostID: "isolated-test" });
  service = await GenerationService.open(
    { dataDirectory: join(directory, "data"), development: true, captureProvider: provider },
    new FakeInference(),
  );
}, 20_000);
afterAll(async () => {
  if (!helper || process.platform !== "linux") return;
  try {
    await service?.shutdown();
    await provider?.close();
  } finally {
    if (daemon && daemon.exitCode === null) {
      daemon.kill();
      await new Promise((resolve) => daemon.once("close", resolve));
    }
    if (previous.runtime === undefined) delete process.env.PIPEWIRE_RUNTIME_DIR;
    else process.env.PIPEWIRE_RUNTIME_DIR = previous.runtime;
    if (previous.remote === undefined) delete process.env.PIPEWIRE_REMOTE;
    else process.env.PIPEWIRE_REMOTE = previous.remote;
    await rm(directory, { recursive: true, force: true });
  }
});
async function begin() {
  await until(async () => ((await service.health()).ready ? true : undefined));
  const source = provider.sources()[0]!;
  const owner = "a".repeat(64);
  const starting = service.captures.start(
    {
      requestID: randomUUID(),
      device: { id: "mac", name: "Mac" },
      mode: "test",
      source: source.identity,
    },
    owner,
  );
  void starting.catch(() => {});
  await connect();
  return { record: await starting, owner };
}
nativeTest(
  "native PipeWire buffers reach existing generations with meters and matching retention intervals",
  async () => {
    for (const retained of [true, false]) {
      const preferences = await service.getPreferences();
      preferences.preferences.keepOriginalAudio = retained;
      await service.updatePreferences(preferences);
      const { record, owner } = await begin();
      await Bun.sleep(500);
      expect((await service.get(record.id)).capture?.peak).toBeGreaterThan(0.1);
      const stopped = await service.captures.stop(record.id, {}, owner);
      expect(stopped.capture?.state).toBe("sealed");
      expect(stopped.inferenceAudio?.sampleRate).toBe(16000);
      expect(stopped.inferenceAudio?.channels).toBe(1);
      expect(stopped.inferenceAudio!.frameCount).toBeGreaterThan(4000);
      if (retained) {
        expect(stopped.originalAudio?.channels).toBe(2);
        expect(stopped.originalAudio?.sampleRate).toBe(48000);
        expect(
          Math.abs(
            stopped.originalAudio!.frameCount / 48000 - stopped.inferenceAudio!.frameCount / 16000,
          ),
        ).toBeLessThan(1 / 16000);
      } else expect(stopped.originalAudio).toBeUndefined();
      await noCapture();
    }
  },
  20_000,
);
nativeTest("cancellation releases native input and allows a new take", async () => {
  const { record } = await begin();
  await service.cancel(record.id);
  await noCapture();
  const next = await begin();
  await service.cancel(next.record.id);
  await noCapture();
});
nativeTest(
  "owner lease expiry kills native capture without sealing",
  async () => {
    const { record } = await begin();
    await Bun.sleep(5300);
    await noCapture();
    expect((await service.get(record.id)).capture?.state).toBe("stopped");
  },
  10_000,
);
nativeTest("wrong target cannot silently attach to another source", async () => {
  const child = spawn(helper!, ["capture", "99999999", "48000", "2", "0"], {
    stdio: ["pipe", "pipe", "ignore"],
  });
  let bytes = 0;
  child.stdout.on("data", (b) => {
    bytes += b.length;
  });
  const completion = new Promise((resolve) => child.once("close", resolve));
  const node = await until(async () =>
    (await graph()).find((x) => x.info?.props?.["media.name"] === "Sotto capture"),
  );
  await configure(node.id, "Input");
  // Force an incorrect link, as a misbehaving session manager might. The helper must reject it.
  await command("pw-link", ["sotto-test-source:capture_FL", "sotto-capture:input_FL"]);
  const code = await completion;
  expect(code).not.toBe(0);
  expect(bytes).toBe(0);
  await noCapture();
});
nativeTest("parent crash kills its native helper", async () => {
  const parent = spawn(
    process.execPath,
    [
      "-e",
      `const p=Bun.spawn([process.argv[1],"capture","13","48000","2","0"],{stdin:"pipe",stdout:"ignore",stderr:"ignore",env:{...process.env,SOTTO_CAPTURE_PARENT_PID:String(process.pid)}}); console.log(p.pid); setInterval(()=>{},1000);`,
      helper!,
    ],
    { stdio: ["ignore", "pipe", "ignore"] },
  );
  const pid = await new Promise<number>((resolve) =>
    parent.stdout.once("data", (bytes) => resolve(Number(bytes.toString().trim()))),
  );
  const exited = new Promise((resolve) => parent.once("close", resolve));
  await connect();
  parent.kill("SIGKILL");
  await exited;
  await until(async () => {
    try {
      const stat = await Bun.file(`/proc/${pid}/stat`).text();
      return stat.split(") ")[1]?.startsWith("Z") ? true : undefined;
    } catch {
      return true;
    }
  });
  await noCapture();
});
nativeTest("service shutdown releases capture and restart permits a fresh take", async () => {
  const { record } = await begin();
  await service.shutdown();
  await provider.close();
  await noCapture();
  provider = await PipeWireCaptureProvider.open({ helper: helper!, hostID: "isolated-test" });
  service = await GenerationService.open(
    { dataDirectory: join(directory, "data"), development: true, captureProvider: provider },
    new FakeInference(),
  );
  expect((await service.get(record.id)).capture?.state).toBe("stopped");
  const next = await begin();
  await service.cancel(next.record.id);
  await noCapture();
});
nativeTest("target removal cancels an active take without substituting audio", async () => {
  const { record } = await begin();
  const source = (await graph()).find((x) => x.info?.props?.["node.name"] === "sotto-test-source")!;
  await command("pw-cli", ["destroy", String(source.id)]);
  await noCapture();
  expect((await service.get(record.id)).capture?.state).toBe("stopped");
});
