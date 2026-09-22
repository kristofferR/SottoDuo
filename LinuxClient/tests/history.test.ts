import { afterEach, expect, test } from "bun:test";
import { mkdtemp, readFile, readdir, rm, stat, symlink, mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { GenerationService } from "../../Server/src/generation-service.ts";
import { createHTTPServer } from "../../Server/src/http-server.ts";
import { FakeInference } from "../../Server/tests/support.ts";
import { API } from "../src/api.ts";
import { HistoryTools } from "../src/history.ts";
const cleanup: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const close of cleanup.splice(0).reverse()) await close();
});
async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "sotto-history-"));
  const runtime = join(directory, "runtime");
  await mkdir(runtime, { mode: 0o700 });
  const previous = process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR = runtime;
  const service = await GenerationService.open(
    { dataDirectory: join(directory, "data"), development: true },
    new FakeInference(),
  );
  const server = createHTTPServer(service, "history-fixture-token");
  const address = await server.listen({ host: "127.0.0.1", port: 0 });
  cleanup.push(async () => {
    await service.shutdown();
    await server.close();
    if (previous === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = previous;
    await rm(directory, { recursive: true, force: true });
  });
  const api = new API(address, "history-fixture-token");
  const tools = new HistoryTools(api);
  const record = await service.create({
    requestID: randomUUID(),
    device: { id: "desktop", name: "Desktop" },
    mode: "test",
  });
  async function complete() {
    await service.appendAudio(
      record.id,
      "inference",
      0,
      { sampleRate: 16000, channels: 1 },
      Buffer.alloc(16000),
    );
    await service.appendAudio(
      record.id,
      "original",
      0,
      { sampleRate: 16000, channels: 1 },
      Buffer.alloc(16000),
    );
    await service.finish(record.id, { inferenceFrames: 4000, originalFrames: 4000 });
    for await (const value of await service.events(record.id))
      if (["completed", "failed", "cancelled"].includes(value.status)) return value;
    throw Error("Missing terminal record");
  }
  return { api, tools, record, complete, address, runtime };
}
test("history reads stay scoped, saved audio is private, and explicit deletion removes shared and cached data", async () => {
  const { tools, record, complete, address, api, runtime } = await fixture();
  await expect(tools.action("deleteHistory", { id: record.id, server: address })).rejects.toThrow(
    "Finish or cancel",
  );
  await complete();
  const page = await tools.list(undefined, "sotto", "query-1");
  expect(page).toMatchObject({ server: address, queryID: "query-1" });
  expect(page.items.map((r) => r.id)).toEqual([record.id]);
  expect((await tools.list(undefined, "wispr-flow", "query-2")).items).toEqual([]);
  const result = await tools.action("historyAudio", {
    id: record.id,
    kind: "inference",
    server: address,
  });
  if (typeof result.url !== "string") throw Error("Expected local audio");
  const path = fileURLToPath(result.url);
  expect(path.startsWith(join(runtime, "sotto-client", "history-audio"))).toBe(true);
  expect((await stat(path)).mode & 0o777).toBe(0o600);
  expect((await readFile(path)).subarray(0, 4).toString()).toBe("RIFF");
  expect(JSON.stringify(result)).not.toContain("history-fixture-token");
  const original = await tools.action("historyAudio", {
    id: record.id,
    kind: "original",
    server: address,
  });
  expect(original).toMatchObject({ kind: "original", id: record.id });
  expect((await api.get(record.id)).status).toBe("completed");
  await tools.action("deleteHistory", { id: record.id, server: address });
  expect((await tools.list(undefined, undefined, "query-3")).items).toEqual([]);
  expect(await readdir(join(runtime, "sotto-client", "history-audio"))).toEqual([]);
  await expect(api.get(record.id)).rejects.toMatchObject({ status: 404 });
});
test("history actions reject wrong servers, paths, missing audio and untrusted download contents", async () => {
  const { tools, record, complete, address, api, runtime } = await fixture();
  await complete();
  await expect(
    tools.action("deleteHistory", { id: record.id, server: "https://other.example" }),
  ).rejects.toThrow("server changed");
  await expect(
    tools.action("historyAudio", { id: "../preferences", server: address }),
  ).rejects.toThrow("valid history");
  await expect(
    tools.action("historyAudio", { id: record.id, kind: "../../token", server: address }),
  ).rejects.toThrow("no saved recording");
  await expect(tools.list(undefined, "untrusted", "q")).rejects.toThrow("all sources");
  const auth = new HistoryTools(new API(address, "wrong-token"));
  await expect(auth.action("deleteHistory", { id: record.id, server: address })).rejects.toThrow(
    "access token",
  );
  api.historyAudio = async () => new Response("not a WAV file");
  await expect(
    tools.action("historyAudio", { id: record.id, kind: "inference", server: address }),
  ).rejects.toThrow("playable WAV");
  api.historyAudio = async () =>
    new Response("", { headers: { "content-length": String(129 * 1024 * 1024) } });
  await expect(
    tools.action("historyAudio", { id: record.id, kind: "inference", server: address }),
  ).rejects.toThrow("too large");
  expect(await readdir(join(runtime, "sotto-client", "history-audio"))).toEqual([]);
  await rm(join(runtime, "sotto-client", "history-audio"), { recursive: true });
  await symlink(runtime, join(runtime, "sotto-client", "history-audio"));
  await expect(
    tools.action("historyAudio", { id: record.id, kind: "inference", server: address }),
  ).rejects.toThrow("private audio folder");
  expect((await api.get(record.id)).status).toBe("completed");
});
