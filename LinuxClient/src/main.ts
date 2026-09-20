import { resolve, dirname } from "node:path";
import { API } from "./api.ts";
import { configPath, initialize, readConfig, token } from "./config.ts";
import { Controller } from "./controller.ts";
import { command, HyprlandDesktop } from "./desktop.ts";
import { isCommand, send, serve, type Command } from "./ipc.ts";

const help = `Sotto for Hyprland
  sotto init SERVER_ORIGIN CAPTURE_HOST_ID TOKEN_FILE [DESTINATION_HELPER]
  sotto sources          List available server capture inputs (no microphone opened)
  sotto daemon           Run the desktop client in the graphical session
  sotto start|stop        Hold-to-talk press/release commands
  sotto toggle|cancel    Toggle recording or cancel this desktop's take
  sotto status|result    Show state or the current process's last result
  sotto copy             Explicitly copy that result; never inject paste keys

Config: ${configPath()}
Set source priorities in this desktop's config, then restart the daemon.
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
  else {
    const config = await readConfig();
    const api = new API(config.server, await token(config));
    if (action === "sources") console.log(JSON.stringify(await api.sources(), null, 2));
    else if (action === "daemon") {
      const desktop = new HyprlandDesktop(config.destinationHelper);
      const controller = new Controller(api, desktop, config.device, config.sources);
      let close: (() => Promise<void>) | undefined;
      const shutdown = async (exitCode = 0) => {
        await controller.cancel();
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
        const handle = async (action: Command): Promise<string> => {
          switch (action) {
            case "start":
              controller.start();
              break;
            case "stop":
              controller.stop();
              break;
            case "toggle":
              controller.toggle();
              break;
            case "cancel":
              await controller.cancel();
              break;
            case "status":
              return controller.state;
            case "result":
              return (
                controller.result?.text ??
                "No result in this session. Check shared history for older takes."
              );
            case "copy": {
              const result = controller.result;
              if (!result || !(await desktop.unlocked()) || controller.result !== result)
                return "No current result to copy, or the desktop is locked.";
              await command(["wl-copy", "--type", "text/plain;charset=utf-8"], 1500, result.text);
              return "Copied. Paste into your chosen field.";
            }
          }
          return controller.state;
        };
        close = await serve(handle, () => {
          void shutdown(1);
        });
        await desktop.monitorSession(
          () => {
            if (
              ["preparing", "processing"].includes(controller.state) ||
              controller.state.startsWith("recording")
            )
              void controller.cancel();
          },
          (action) => {
            void handle(action).catch(() => desktop.notify("Shortcut failed."));
          },
        );
        console.log("Sotto is ready. Waiting for a shortcut.");
      } catch (error) {
        desktop.close();
        await close?.();
        throw error;
      }
    } else throw new Error("Unknown command. Use sotto --help.");
  }
} catch (error) {
  // Do not dump request objects, headers, server response text or credentials.
  console.error(error instanceof Error ? error.message : "Sotto failed.");
  process.exitCode = 1;
}
