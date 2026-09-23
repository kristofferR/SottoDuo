import { expect, test } from "bun:test";
import { resolve } from "node:path";
// Opt in only in a disposable test display or during an explicitly supervised desktop trial.
const nativeTest = process.env.SOTTO_TEST_DESKTOP === "1" ? test : test.skip;
nativeTest(
  "real GTK field: Unicode insertion once; changed text/caret/selection/focus/password reject",
  async () => {
    const root = resolve(import.meta.dir, "../..");
    const helper = `${root}/build/linux-client/sotto-destination`;
    const entry = Bun.spawn([`${root}/.local/entry-fixture`], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "ignore",
    });
    const reader = entry.stdout.getReader();
    const read = async () => new TextDecoder().decode((await reader.read()).value).trimEnd();
    const send = async (value: string) => {
      entry.stdin.write(value + "\n");
      await entry.stdin.flush();
      await Bun.sleep(150);
    };
    try {
      expect(await read()).toBe("ready");
      await Bun.sleep(900);
      for (const change of [undefined, "change", "caret", "select", "other", "password"]) {
        await send("reset");
        const destination = Bun.spawn([helper, String(entry.pid)], {
          stdin: "pipe",
          stdout: "pipe",
          stderr: "pipe",
        });
        const output = destination.stdout.getReader();
        const deadline = setTimeout(() => destination.kill(), 4000);
        try {
          expect(new TextDecoder().decode((await output.read()).value).trim()).toBe("ready");
          if (change) await send(change);
          destination.stdin.write(JSON.stringify("Hei æøå 👋") + "\n");
          await destination.stdin.flush();
          const result = new TextDecoder().decode((await output.read()).value).trim();
          expect(result).toBe(change ? "preview" : "inserted");
          await send("get");
          expect(await read()).toBe(
            change === "change" ? "changed" : change ? "start" : "start Hei æøå 👋",
          );
        } finally {
          clearTimeout(deadline);
          destination.kill();
        }
      }
      await send("reset");
      await send("password");
      const password = Bun.spawn([helper, String(entry.pid)], {
        stdin: "ignore",
        stdout: "pipe",
        stderr: "ignore",
      });
      expect((await new Response(password.stdout).text()).trim()).toBe("preview");
    } finally {
      entry.kill();
    }
  },
  20000,
);

nativeTest(
  "Hyprland destination adapter inserts once and rejects a vanished application",
  async () => {
    const { HyprlandDesktop } = await import("../src/desktop.ts");
    const root = resolve(import.meta.dir, "../..");
    const desktop = new HyprlandDesktop(`${root}/build/linux-client/sotto-destination`);
    await desktop.monitorSession(() => {});
    const entry = Bun.spawn([`${root}/.local/entry-fixture`], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "ignore",
    });
    const reader = entry.stdout.getReader();
    try {
      await reader.read();
      await Bun.sleep(800);
      expect(await desktop.unlocked()).toBe(true);
      const destination = await desktop.capture();
      expect(await destination.deliver("Norsk æøå")).toBe("inserted");
      expect(await destination.deliver("duplicate")).toBe("preview");
      entry.stdin.write("get\n");
      await entry.stdin.flush();
      expect(new TextDecoder().decode((await reader.read()).value).trim()).toBe("start Norsk æøå");
      entry.stdin.write("reset\n");
      await entry.stdin.flush();
      await Bun.sleep(100);
      const gone = await desktop.capture();
      entry.kill();
      await entry.exited;
      await Bun.sleep(100);
      expect(await gone.deliver("must not be inserted elsewhere")).toBe("preview");
    } finally {
      entry.kill();
      desktop.close();
    }
  },
  10000,
);
