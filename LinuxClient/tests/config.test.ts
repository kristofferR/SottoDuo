import { expect, test } from "bun:test";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { configPath, endpoint, parseConfig } from "../src/config.ts";
test("endpoint changes cannot silently reuse another server's microphone preferences", () => {
  const value = {
    server: "http://localhost:8391",
    tokenFile: "/private/token",
    destinationHelper: "/opt/sottoduo-destination",
    device: { id: "desktop", name: "Omarchy" },
    sources: {
      server: "http://localhost:8391",
      hostID: "desktop",
      mode: "automatic",
      priority: [],
    },
  };
  expect(parseConfig(value).sources.hostID).toBe("desktop");
  expect(() => parseConfig({ ...value, server: "http://other-server:8391" })).toThrow(
    "another server",
  );
  expect(() => endpoint("https://secret@example.com")).toThrow();
  expect(() => endpoint("http://localhost:8391/v1")).toThrow();
  expect(() => parseConfig({ ...value, sources: { ...value.sources, mode: "fixed" } })).toThrow(
    "source identity",
  );
});

test("an empty XDG config directory uses the home config path", () => {
  const previousConfig = process.env.SOTTODUO_CLIENT_CONFIG;
  const previousLegacy = process.env.SOTTO_CLIENT_CONFIG;
  const previousXDG = process.env.XDG_CONFIG_HOME;
  try {
    delete process.env.SOTTODUO_CLIENT_CONFIG;
    delete process.env.SOTTO_CLIENT_CONFIG;
    process.env.XDG_CONFIG_HOME = "";
    const homeConfig = join(homedir(), ".config");
    const legacy = join(homeConfig, "sotto", "linux-client.json");
    expect(configPath()).toBe(
      existsSync(legacy) ? legacy : join(homeConfig, "sottoduo", "linux-client.json"),
    );
  } finally {
    if (previousConfig === undefined) delete process.env.SOTTODUO_CLIENT_CONFIG;
    else process.env.SOTTODUO_CLIENT_CONFIG = previousConfig;
    if (previousLegacy === undefined) delete process.env.SOTTO_CLIENT_CONFIG;
    else process.env.SOTTO_CLIENT_CONFIG = previousLegacy;
    if (previousXDG === undefined) delete process.env.XDG_CONFIG_HOME;
    else process.env.XDG_CONFIG_HOME = previousXDG;
  }
});

test("existing Linux config and legacy override survive the rename", async () => {
  const directory = await mkdtemp(join(tmpdir(), "sottoduo-config-"));
  const previous = {
    current: process.env.SOTTODUO_CLIENT_CONFIG,
    legacy: process.env.SOTTO_CLIENT_CONFIG,
    xdg: process.env.XDG_CONFIG_HOME,
  };
  try {
    delete process.env.SOTTODUO_CLIENT_CONFIG;
    delete process.env.SOTTO_CLIENT_CONFIG;
    process.env.XDG_CONFIG_HOME = directory;
    const legacy = join(directory, "sotto", "linux-client.json");
    const current = join(directory, "sottoduo", "linux-client.json");
    expect(configPath()).toBe(current);
    await mkdir(join(directory, "sotto"));
    await writeFile(legacy, "{}");
    expect(configPath()).toBe(legacy);
    await mkdir(join(directory, "sottoduo"));
    await writeFile(current, "{}");
    expect(configPath()).toBe(current);
    process.env.SOTTO_CLIENT_CONFIG = legacy;
    expect(configPath()).toBe(legacy);
    process.env.SOTTODUO_CLIENT_CONFIG = current;
    expect(configPath()).toBe(current);
  } finally {
    if (previous.current === undefined) delete process.env.SOTTODUO_CLIENT_CONFIG;
    else process.env.SOTTODUO_CLIENT_CONFIG = previous.current;
    if (previous.legacy === undefined) delete process.env.SOTTO_CLIENT_CONFIG;
    else process.env.SOTTO_CLIENT_CONFIG = previous.legacy;
    if (previous.xdg === undefined) delete process.env.XDG_CONFIG_HOME;
    else process.env.XDG_CONFIG_HOME = previous.xdg;
    await rm(directory, { recursive: true, force: true });
  }
});
