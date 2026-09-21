import { expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { Controller, type Desktop } from "../src/controller.ts";
import { API } from "../src/api.ts";
import { createGUIHandler } from "../src/gui.ts";
import { parseConfig } from "../src/config.ts";

test("GUI requests are versioned and scoped; source preferences persist without losing private configuration", async () => {
  const dir = await mkdtemp(join(tmpdir(), "sotto-gui-"));
  const previous = process.env.SOTTO_CLIENT_CONFIG;
  process.env.SOTTO_CLIENT_CONFIG = join(dir, "client.json");
  const config = parseConfig({
    server: "http://localhost:8394",
    tokenFile: "/private/token",
    destinationHelper: "/private/helper",
    device: { id: "desktop", name: "Desktop" },
    sources: {
      server: "http://localhost:8394",
      hostID: "desktop",
      mode: "automatic",
      priority: [],
    },
  });
  let unlocked = true;
  const desktop: Desktop = {
    unlocked: async () => unlocked,
    capture: async () => {
      throw new Error("not used");
    },
    defaultInput: async () => undefined,
    notify() {},
  };
  const api = new API(config.server, "never-publish-this-token");
  const controller = new Controller(api, desktop, config.device, config.sources);
  const gui = createGUIHandler(api, controller, desktop, config);
  try {
    await writeFile(process.env.SOTTO_CLIENT_CONFIG, JSON.stringify(config), { mode: 0o600 });
    await expect(gui({ version: 2, action: "snapshot" })).rejects.toThrow();
    await expect(gui({ version: 1, action: "request", path: "/anything" })).rejects.toThrow();
    const snapshot = JSON.stringify(await gui({ version: 1, action: "snapshot" }));
    expect(snapshot).not.toContain("/private");
    expect(snapshot).not.toContain("never-publish");
    const sources = { ...config.sources, priority: [{ hostID: "desktop", id: "dji" }] };
    await gui({ version: 1, action: "saveSources", value: sources });
    expect(JSON.parse(await readFile(process.env.SOTTO_CLIENT_CONFIG, "utf8"))).toEqual({
      ...config,
      sources,
    });
    unlocked = false;
    await expect(gui({ version: 1, action: "saveSources", value: config.sources })).rejects.toThrow(
      "Unlock",
    );
    unlocked = true;
    await writeFile(
      process.env.SOTTO_CLIENT_CONFIG,
      JSON.stringify({ ...config, device: { ...config.device, name: "External change" } }),
    );
    await expect(gui({ version: 1, action: "saveSources", value: config.sources })).rejects.toThrow(
      "externally",
    );
  } finally {
    if (previous === undefined) delete process.env.SOTTO_CLIENT_CONFIG;
    else process.env.SOTTO_CLIENT_CONFIG = previous;
    await rm(dir, { recursive: true, force: true });
  }
});

test("shared GUI settings preserve untouched preferences and reject a stale revision", async () => {
  const { GenerationService } = await import("../../Server/src/generation-service.ts");
  const { createHTTPServer } = await import("../../Server/src/http-server.ts");
  const { FakeInference } = await import("../../Server/tests/support.ts");
  const dir = await mkdtemp(join(tmpdir(), "sotto-gui-prefs-"));
  const service = await GenerationService.open(
    { dataDirectory: dir, development: true },
    new FakeInference(),
  );
  const server = createHTTPServer(service, "test-token");
  try {
    const endpoint = await server.listen({ host: "127.0.0.1", port: 0 });
    const api = new API(endpoint, "test-token");
    const old = await api.preferences();
    const current = await api.savePreferences({
      ...old,
      preferences: {
        ...old.preferences,
        proofreadingPrompt: "Preserve this prompt",
        vocabulary: "First computer",
      },
    });
    await expect(
      api.savePreferences({
        ...old,
        preferences: { ...old.preferences, vocabulary: "Stale computer" },
      }),
    ).rejects.toThrow("409");
    const saved = await api.savePreferences({
      ...current,
      preferences: { ...current.preferences, vocabulary: "Current computer" },
    });
    expect(saved.preferences.proofreadingPrompt).toBe("Preserve this prompt");
    expect(saved.preferences.vocabulary).toBe("Current computer");
  } finally {
    await service.shutdown();
    await server.close();
    await rm(dir, { recursive: true, force: true });
  }
});
