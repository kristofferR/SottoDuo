import { expect, test } from "bun:test";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { send, serve } from "../src/ipc.ts";

test("private IPC serializes commands, rejects a second daemon and releases its lock", async () => {
  const dir = await mkdtemp(join(tmpdir(), "sotto-ipc-"));
  const previous = process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR = dir;
  let close: (() => Promise<void>) | undefined;
  try {
    const calls: string[] = [];
    close = await serve(async (command) => {
      calls.push(command);
      return "ok";
    });
    expect((await stat(join(dir, "sotto-client", "control.sock"))).mode & 0o777).toBe(0o600);
    expect(await send("start")).toBe("ok\n");
    expect(await send("stop")).toBe("ok\n");
    expect(calls).toEqual(["start", "stop"]);
    await expect(serve(async () => "other")).rejects.toThrow("lock");
    expect(await send("status")).toBe("ok\n");
    await close();
    close = await serve(async () => "new process, no take");
    expect(await send("status")).toBe("new process, no take\n");
  } finally {
    await close?.();
    if (previous === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = previous;
    await rm(dir, { recursive: true, force: true });
  }
});
