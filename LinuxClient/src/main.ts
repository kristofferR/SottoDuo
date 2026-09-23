import { resolve, dirname } from "node:path";
import { API } from "./api.ts";
import { configPath, initialize, readConfig, token } from "./config.ts";
import { ConnectionSettings } from "./connection.ts";
import { command, HyprlandDesktop } from "./desktop.ts";
import { isCommand, send, serve } from "./ipc.ts";
import { isPlasmaDesktop, PlasmaDesktop } from "./plasma.ts";
import { ClientRuntime } from "./runtime.ts";
import { ShortcutSettings } from "./shortcuts.ts";

const help = `Sotto for Linux
  sotto init SERVER_ORIGIN CAPTURE_HOST_ID TOKEN_FILE [DESTINATION_HELPER]
  sotto sources          List available server capture inputs (no microphone opened)
  sotto daemon           Run the desktop client in the graphical session
  sotto start|stop        Hold-to-talk press/release commands
  sotto toggle|cancel    Toggle recording or cancel this desktop's take
  sotto status|result    Show state or the current process's last result
  sotto arm|disarm       Select or clear this computer for the DJI pairing button
  sotto button-status    Show button destination and receiver availability
  sotto copy             Explicitly copy that result; never inject paste keys

Config: ${configPath()}
Configure the connection and microphones in Sotto → This computer.
No recording, insertion, or device ownership resumes after restart.`;

try {
  const [action, ...args] = process.argv.slice(2);
  if (!action || action === "--help") console.log(help);
  else if (action === "init") {
    const [server, hostID, tokenFile, helper] = args;
    if (!server || !hostID || !tokenFile)
      throw new Error("init requires server, host ID and token file.");
    await initialize(
      server,
      hostID,
      resolve(tokenFile),
      resolve(helper ?? `${dirname(process.execPath)}/sotto-destination`),
    );
    console.log(`Created ${configPath()}`);
  } else if (isCommand(action)) process.stdout.write(await send(action));
  else if (action === "sources") {
    const config = await readConfig();
    const api = new API(config.server, await token(config));
    console.log(JSON.stringify(await api.sources(), null, 2));
  } else if (action === "daemon") {
    const helper = resolve(`${dirname(process.execPath)}/sotto-destination`);
    const settings = await ConnectionSettings.open(helper);
    const plasma = isPlasmaDesktop([
      process.env.XDG_CURRENT_DESKTOP,
      process.env.XDG_SESSION_DESKTOP,
      process.env.DESKTOP_SESSION,
    ]);
    const desktop = plasma
      ? new PlasmaDesktop(settings.config?.destinationHelper ?? helper)
      : new HyprlandDesktop(settings.config?.destinationHelper ?? helper);
    const runtime = new ClientRuntime(settings, desktop);
    if (!plasma)
      runtime.shortcuts = new ShortcutSettings(
        (args) => command(args, 3000),
        () => runtime.busy,
      );
    let close: (() => Promise<void>) | undefined;
    const shutdown = async (exitCode = 0) => {
      await runtime.close();
      desktop.close();
      await close?.();
      process.exit(exitCode);
    };
    process.once("SIGTERM", () => {
      void shutdown();
    });
    process.once("SIGINT", () => {
      void shutdown();
    });
    try {
      runtime.start();
      close = await serve(
        (action) => runtime.command(action),
        () => {
          void shutdown(1);
        },
        (request) => runtime.gui(request),
      );
      if (desktop instanceof HyprlandDesktop) {
        await desktop.monitorSession(
          () => runtime.unsafe(),
          (action) => {
            void runtime.command(action).catch(() => desktop.notify("Shortcut failed."));
          },
        );
        await runtime.shortcuts?.refresh();
      } else {
        await desktop.monitorSession(() => runtime.unsafe());
      }
      console.log(
        settings.api
          ? "Sotto is ready. Waiting for a shortcut."
          : "Open Sotto → This computer to set up the server connection.",
      );
    } catch (error) {
      await runtime.close();
      desktop.close();
      await close?.();
      throw error;
    }
  } else throw new Error("Unknown command. Use sotto --help.");
} catch (error) {
  // Do not dump request objects, headers, server response text or credentials.
  console.error(error instanceof Error ? error.message : "Sotto failed.");
  process.exitCode = 1;
}
