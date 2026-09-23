import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseConfiguration } from "../src/configuration.ts";

const directories: string[] = [];
afterEach(async () => {
  for (const directory of directories.splice(0))
    await rm(directory, { recursive: true, force: true });
});
const environment = {
  SOTTODUO_SERVER_DATA_DIR: "/tmp/sottoduo-config",
  SOTTODUO_ENGINE_PATH: "/tmp/speech",
  SOTTODUO_SPEECH_MODEL: "/tmp/speech-model",
  SOTTODUO_VAD_PATH: "/tmp/vad",
  SOTTODUO_TEXT_ENGINE_PATH: "/tmp/proof",
  SOTTODUO_TEXT_MODEL: "/tmp/proof-model",
};

test("PipeWire capture is opt-in and requires a stable host identity", async () => {
  expect((await parseConfiguration([], environment)).capture).toBeUndefined();
  await expect(
    parseConfiguration(["--capture-helper", "/tmp/capture"], environment),
  ).rejects.toThrow("both");
  await expect(
    parseConfiguration(
      ["--capture-helper", "/tmp/capture", "--capture-host-id", "invalid id"],
      environment,
    ),
  ).rejects.toThrow("stable");
  expect(
    (
      await parseConfiguration(
        ["--capture-helper", "/tmp/capture", "--capture-host-id", "desktop"],
        environment,
      )
    ).capture,
  ).toEqual({ helper: "/tmp/capture", hostID: "desktop" });
});

test("CLI overrides environment and uses independent explicit model/data paths", async () => {
  const configuration = await parseConfiguration(["--port", "8392", "--dev"], {
    ...environment,
    SOTTODUO_SERVER_PORT: "8391",
  });
  expect(configuration).toMatchObject({
    host: "127.0.0.1",
    port: 8392,
    development: true,
    dataDirectory: "/tmp/sottoduo-config",
    inference: { speechHelper: "/tmp/speech", proofModel: "/tmp/proof-model" },
  });
  for (const port of ["0", "65536", "12oops", "1.2", "NaN"])
    await expect(parseConfiguration(["--port", port], environment)).rejects.toThrow("Port");
  await expect(parseConfiguration(["--unknown", "value"], environment)).rejects.toThrow("Unknown");
  await expect(parseConfiguration([], {})).rejects.toThrow("Configure");
});

test("deployed SOTTO environment names remain valid with new names taking precedence", async () => {
  const old = Object.fromEntries(
    Object.entries(environment).map(([name, value]) => [
      name.replace("SOTTODUO_", "SOTTO_"),
      value,
    ]),
  );
  const config = await parseConfiguration([], {
    ...old,
    SOTTO_DEV: "1",
    SOTTO_SERVER_PORT: "8392",
  });
  expect(config).toMatchObject({
    development: true,
    port: 8392,
    dataDirectory: "/tmp/sottoduo-config",
    inference: { speechHelper: "/tmp/speech", proofModel: "/tmp/proof-model" },
  });
  expect(
    (await parseConfiguration([], { ...old, SOTTODUO_SERVER_DATA_DIR: "/tmp/new" })).dataDirectory,
  ).toBe("/tmp/new");
});

test("remote listeners require a bounded regular UTF8 token file", async () => {
  await expect(parseConfiguration(["--host", "0.0.0.0"], environment)).rejects.toThrow(
    "requires a token",
  );
  const directory = await mkdtemp(join(tmpdir(), "sottoduo-config-"));
  directories.push(directory);
  const file = join(directory, "token");
  await writeFile(file, `${"x".repeat(32)}\n`);
  const configuration = await parseConfiguration(
    ["--host", "0.0.0.0", "--token-file", file],
    environment,
  );
  expect(configuration.token).toBe("x".repeat(32));
  const link = join(directory, "link");
  await symlink(file, link);
  await expect(parseConfiguration(["--token-file", link], environment)).rejects.toThrow();
  await writeFile(file, "short");
  await expect(
    parseConfiguration(["--host", "0.0.0.0", "--token-file", file], environment),
  ).rejects.toThrow("requires a token");
  await writeFile(file, "x".repeat(4097));
  await expect(parseConfiguration(["--token-file", file], environment)).rejects.toThrow("4096");
  await writeFile(file, "x y");
  await expect(parseConfiguration(["--token-file", file], environment)).rejects.toThrow(
    "whitespace",
  );
});

test("Soniox credentials are optional, bounded, server-only, and may come from a private file", async () => {
  expect((await parseConfiguration([], environment)).soniox).toBeUndefined();
  expect(
    (await parseConfiguration([], { ...environment, SONIOX_API_KEY: "api-secret" })).soniox,
  ).toEqual({
    apiKey: "api-secret",
    model: "stt-rt-v5",
    endpoint: "wss://stt-rt.soniox.com/transcribe-websocket",
  });
  const directory = await mkdtemp(join(tmpdir(), "sottoduo-soniox-config-"));
  directories.push(directory);
  const file = join(directory, "key");
  await writeFile(file, "file-secret\n", { mode: 0o600 });
  expect(
    (
      await parseConfiguration(["--soniox-key-file", file], {
        ...environment,
        SONIOX_API_KEY: "env-secret",
      })
    ).soniox?.apiKey,
  ).toBe("file-secret");
  await writeFile(file, "\n");
  await expect(parseConfiguration(["--soniox-key-file", file], environment)).rejects.toThrow(
    "Soniox key",
  );
  await expect(
    parseConfiguration([], { ...environment, SONIOX_API_KEY: "bad key" }),
  ).rejects.toThrow("Soniox key");
});

test("button capture requires explicit helper, capture provider and exact stable source", async () => {
  expect((await parseConfiguration([], environment)).button).toBeUndefined();
  const args = ["--capture-helper", "/tmp/capture", "--capture-host-id", "desktop"];
  for (const extra of [
    ["--button-helper", "/tmp/button"],
    ["--button-source-id", "dji"],
    ["--button-helper", "/tmp/button", "--button-source-id", "dji"],
  ])
    await expect(parseConfiguration([...args, ...extra], environment)).rejects.toThrow(
      "Button routing",
    );
  const sourceID = "a".repeat(64);
  expect(
    (
      await parseConfiguration(
        [...args, "--button-helper", "/tmp/button", "--button-source-id", sourceID],
        environment,
      )
    ).button,
  ).toEqual({ helper: "/tmp/button", sourceID });
});
