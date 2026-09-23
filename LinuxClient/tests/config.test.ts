import { expect, test } from "bun:test";
import { endpoint, parseConfig } from "../src/config.ts";
test("endpoint changes cannot silently reuse another server's microphone preferences", () => {
  const value = {
    server: "http://localhost:8391",
    tokenFile: "/private/token",
    destinationHelper: "/opt/sotto-destination",
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
