import { readdir, readFile, realpath } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import type { ButtonDestinations } from "../button-destinations.ts";
import type { PipeWireInput } from "./pipewire-discovery.ts";
import { captureHelper } from "./helper.ts";

/** Native helper timestamps are Unix milliseconds, shared across process runtimes. */
export function buttonPress(line: string, now = Date.now()): number | undefined {
  if (!/^press [1-9]\d* \d+$/.test(line)) return;
  const [, sequence, timestamp] = line.split(" ");
  const age = now - Number(timestamp);
  if (Number.isSafeInteger(Number(sequence)) && age >= 0 && age <= 250) return Number(sequence);
}

export class DJIButtonInput {
  private running?: { key: string; process: ReturnType<typeof captureHelper> };
  private retryAt = 0;
  private closed = false;
  constructor(
    private helper: string,
    private sourceID: string,
    private router: ButtonDestinations,
  ) {}
  async refresh(inputs: PipeWireInput[]) {
    if (this.closed) return;
    const input = inputs.find((i) => i.dji && i.source.identity.id === this.sourceID);
    let path: string | undefined, usb: string | undefined;
    if (input?.card !== undefined) {
      try {
        usb = dirname(await realpath(`/sys/class/sound/card${input.card}/device`));
        for (const event of await readdir("/sys/class/input")) {
          if (!/^event\d+$/.test(event)) continue;
          const sys = `/sys/class/input/${event}/device`;
          if (
            (await readFile(join(sys, "name"), "utf8")).trim() !==
            "DJI Technology Co., Ltd. Wireless Mic Rx Consumer Control"
          )
            continue;
          if ((await realpath(sys)).startsWith(usb + "/")) {
            path = `/dev/input/${event}`;
            break;
          }
        }
      } catch {
        /* Unknown association cannot authorize a button. */
      }
    }
    const key = input && path && usb ? JSON.stringify([input.serial, path, usb]) : undefined;
    if (this.running && this.running.key !== key) await this.stop();
    if (
      this.closed ||
      this.running ||
      !key ||
      !input ||
      !path ||
      !usb ||
      performance.now() < this.retryAt
    )
      return;
    const process = captureHelper(this.helper, [path, usb]);
    const running = { key, process };
    this.running = running;
    const epoch = randomUUID();
    let ready = false,
      buffer = "";
    const startup = setTimeout(() => {
      if (this.running === running && !ready) void this.stop();
    }, 2000);
    startup.unref();
    process.child.stdout.on("data", (data: Buffer) => {
      if (this.running !== running || this.closed) return;
      buffer += data.toString();
      if (buffer.length > 4096) {
        void this.stop();
        return;
      }
      let at: number;
      while ((at = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, at);
        buffer = buffer.slice(at + 1);
        if (!ready && line === "ready") {
          ready = true;
          clearTimeout(startup);
          this.router.input(input.source.identity, epoch);
        } else if (ready && /^press [1-9]\d* \d+$/.test(line)) {
          const sequence = buttonPress(line);
          if (sequence !== undefined) this.router.press(epoch, sequence);
        } else {
          void this.stop();
          return;
        }
      }
    });
    void process.completion.then(() => {
      clearTimeout(startup);
      if (this.running === running) {
        this.running = undefined;
        this.router.input(undefined);
        this.retryAt = performance.now() + 5000;
      }
    });
  }
  private async stop() {
    const running = this.running;
    this.running = undefined;
    this.retryAt = performance.now() + 5000;
    this.router.input(undefined);
    await running?.process.kill();
  }
  async close() {
    this.closed = true;
    await this.stop();
  }
}
