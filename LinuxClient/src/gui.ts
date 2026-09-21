import { readFileSync, writeFileSync, renameSync, unlinkSync } from "node:fs";
import { API } from "./api.ts";
import { configPath, parseConfig, type Config } from "./config.ts";
import type { Controller, Desktop } from "./controller.ts";
import type { ButtonDestinationClient } from "./buttons.ts";
import { candidates, eligible } from "./sources.ts";

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
/** Deliberately small API: no arbitrary server paths, credentials or capture ownership tokens. */
export function createGUIHandler(
  api: API,
  controller: Controller,
  desktop: Desktop,
  initial: Config,
  buttons?: ButtonDestinationClient,
) {
  let config = initial;
  return async (request: unknown): Promise<unknown> => {
    if (!object(request) || request.version !== 1 || typeof request.action !== "string")
      throw new Error("Unsupported GUI request.");
    if (request.action === "snapshot")
      return {
        version: 1,
        activity: controller.activity,
        busy: controller.busy,
        message: controller.state,
        result: controller.result ?? null,
        device: config.device,
        server: config.server,
        sources: config.sources,
        buttonEnabled: config.buttonEnabled,
        button: buttons?.state
          ? { selected: buttons.state.selected, available: buttons.state.available }
          : null,
        desktop: "hyprland",
        configPath: configPath(),
      };
    if (!(await desktop.unlocked())) throw new Error("Unlock this computer first.");
    switch (request.action) {
      case "test":
        controller.start(undefined, true);
        return {};
      case "stop":
        controller.stop();
        return {};
      case "cancel":
        await controller.cancel();
        return {};
      case "arm":
        if (!buttons) throw new Error("Pairing-button support is disabled.");
        await buttons.select();
        return {};
      case "disarm":
        await buttons?.disarm();
        return {};
      case "connection":
        return api.health();
      case "sources": {
        const [sources, defaultID] = await Promise.all([
          api.sources(),
          desktop.defaultInput(config.sources.hostID),
        ]);
        return {
          items: sources.map((source) => ({ ...source, eligible: eligible(source) })),
          next: candidates(sources, config.sources, defaultID)[0] ?? null,
        };
      }
      case "history":
        if (
          request.before !== undefined &&
          (typeof request.before !== "string" || request.before.length > 512)
        )
          throw new Error("Invalid cursor.");
        return api.history(request.before);
      case "preferences":
        return api.preferences();
      case "savePreferences":
        return api.savePreferences(request.value);
      case "saveSources": {
        if (controller.busy) throw new Error("Finish dictation first.");
        const next = parseConfig({ ...config, sources: request.value });
        // Synchronous compare-and-replace keeps new takes and settings writes ordered.
        const disk = parseConfig(JSON.parse(readFileSync(configPath(), "utf8")));
        if (JSON.stringify(disk) !== JSON.stringify(config))
          throw new Error("Configuration changed externally. Restart the client.");
        const temp = `${configPath()}.${process.pid}.tmp`;
        writeFileSync(temp, JSON.stringify(next, null, 2) + "\n", { mode: 0o600, flag: "wx" });
        try {
          renameSync(temp, configPath());
        } finally {
          try {
            unlinkSync(temp);
          } catch {}
        }
        config = next;
        controller.updatePreferences(config.sources);
        return config.sources;
      }
      default:
        throw new Error("Unknown GUI action.");
    }
  };
}
