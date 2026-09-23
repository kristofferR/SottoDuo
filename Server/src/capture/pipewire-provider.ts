import { execFile } from "node:child_process";
import { access, readFile, realpath } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import type { CaptureProvider } from "../capture-sessions.ts";
import { DJIStatus } from "./dji-status.ts";
import { captureHelper } from "./helper.ts";
import { pipeWireInputs, type PipeWireInput } from "./pipewire-discovery.ts";
import { recordPipeWire } from "./pipewire-recording.ts";
import { DJIButtonInput } from "./dji-button.ts";
import type { ButtonDestinations } from "../button-destinations.ts";

export interface PipeWireConfiguration {
  helper: string;
  hostID: string;
}
const exec = promisify(execFile);
interface Probe {
  serial: string;
  status: DJIStatus;
  process: ReturnType<typeof captureHelper>;
  exited: boolean;
  retryAt: number;
}

/** Runs as the desktop user alongside inference, without an audio stream while idle.
 * The optional child boundary isolates native capture and gives it a parent-death kill. */
export class PipeWireCaptureProvider implements CaptureProvider {
  private inputs: PipeWireInput[] = [];
  private probes = new Map<string, Probe>();
  private timer?: ReturnType<typeof setTimeout>;
  private closed = false;
  private buttons?: DJIButtonInput;
  private refreshWork: Promise<void> = Promise.resolve();
  private active?: {
    input: PipeWireInput;
    mask?: number;
    recording: ReturnType<typeof recordPipeWire>;
    lost(): void;
  };
  private constructor(private readonly configuration: PipeWireConfiguration) {}

  attachButtons(helper: string, sourceID: string, router: ButtonDestinations) {
    this.buttons = new DJIButtonInput(helper, sourceID, router);
  }

  static async open(configuration: PipeWireConfiguration) {
    if (process.platform !== "linux") throw new Error("PipeWire capture requires Linux.");
    const provider = new PipeWireCaptureProvider(configuration);
    await provider.poll();
    return provider;
  }
  private async poll() {
    this.refreshWork = this.refresh();
    await this.refreshWork;
    if (!this.closed) {
      this.timer = setTimeout(() => {
        void this.poll();
      }, 1_000);
      this.timer.unref();
    }
  }
  private async refresh() {
    try {
      await access(this.configuration.helper, constants.X_OK);
      const { stdout } = await exec("pw-dump", [], {
        timeout: 2_000,
        maxBuffer: 8_388_608,
        killSignal: "SIGKILL",
        encoding: "utf8",
      });
      if (this.closed) return;
      this.inputs = pipeWireInputs(JSON.parse(stdout), this.configuration.hostID);
      for (const [id, probe] of this.probes) {
        const input = this.inputs.find(
          (i) => i.source.identity.id === id && i.serial === probe.serial,
        );
        if (!input || (probe.exited && performance.now() >= probe.retryAt)) {
          this.probes.delete(id);
          await probe.process.kill();
        }
      }
      for (const input of this.inputs) {
        if (!input.dji || this.probes.has(input.source.identity.id) || input.card === undefined)
          continue;
        try {
          const path = dirname(await realpath(`/sys/class/sound/card${input.card}/device`));
          const [bus, address] = await Promise.all([
            readFile(join(path, "busnum"), "utf8"),
            readFile(join(path, "devnum"), "utf8"),
          ]);
          if (this.closed) return;
          if (!/^\d+\s*$/.test(bus) || !/^\d+\s*$/.test(address)) continue;
          const process = captureHelper(this.configuration.helper, [
            "status",
            bus.trim(),
            address.trim(),
          ]);
          const probe: Probe = {
            serial: input.serial,
            status: new DJIStatus(),
            process,
            exited: false,
            retryAt: 0,
          };
          this.probes.set(input.source.identity.id, probe);
          process.child.stdout.on("data", (bytes: Buffer) => {
            try {
              probe.status.push(bytes);
            } catch {
              void process.kill();
            }
            this.checkActive();
          });
          void process.completion.then(() => {
            probe.exited = true;
            probe.retryAt = performance.now() + 5_000;
            this.checkActive();
          });
        } catch {
          /* Missing sysfs mapping remains unavailable; never guess another receiver. */
        }
      }
    } catch {
      this.inputs = [];
      const probes = [...this.probes.values()];
      this.probes.clear();
      await Promise.all(probes.map((probe) => probe.process.kill()));
    }
    this.checkActive();
    await this.buttons?.refresh(this.inputs);
  }
  sources() {
    return this.inputs.map((input) => {
      const source = structuredClone(input.source);
      if (!input.dji) return source;
      const probe = this.probes.get(source.identity.id);
      const status = probe && !probe.exited ? probe.status.snapshot() : undefined;
      source.link = status ? (status.mask ? "connected" : "disconnected") : "unknown";
      if (source.capture !== "unavailable") {
        source.capture = status?.mask ? "available" : status ? "unavailable" : "unknown";
        source.reason =
          !probe || probe.exited
            ? "DJI status reader unavailable. Check USB permissions or another application using the status interface."
            : !status
              ? "Waiting for fresh DJI transmitter status."
              : !status.mask
                ? "The DJI transmitter is disconnected."
                : "DJI link is connected. RF audio health and transmitter mute are not reported by this decoder.";
      }
      // Link connectivity is not an audio-health claim, including during digital silence.
      source.audioHealth = "unknown";
      return source;
    });
  }
  private checkActive() {
    const active = this.active;
    if (!active) return;
    const current = this.inputs.find(
      (i) => i.source.identity.id === active.input.source.identity.id,
    );
    const source = this.sources().find((i) => i.identity.id === active.input.source.identity.id);
    const mask = this.probes.get(active.input.source.identity.id)?.status.snapshot()?.mask;
    if (
      this.closed ||
      !current ||
      current.serial !== active.input.serial ||
      source?.capture !== "available" ||
      (active.input.dji && mask !== active.mask)
    ) {
      void active.recording.cancel();
      active.lost();
    }
  }
  async start(options: Parameters<CaptureProvider["start"]>[0]) {
    const identity = options.generation.capture?.source;
    const input = this.inputs.find(
      (i) => i.source.identity.hostID === identity?.hostID && i.source.identity.id === identity.id,
    );
    const source = this.sources().find((i) => i.identity.id === identity?.id);
    if (
      this.closed ||
      this.active ||
      !input?.format ||
      source?.capture !== "available" ||
      Date.now() - Date.parse(source.observedAt) > 3_500
    )
      throw new Error("The selected input is unavailable.");
    const recording = recordPipeWire(this.configuration.helper, input, options);
    const active = {
      input,
      mask: this.probes.get(input.source.identity.id)?.status.snapshot()?.mask,
      recording,
      lost: options.lost,
    };
    this.active = active;
    void recording.done.then(() => {
      if (this.active === active) this.active = undefined;
      // Keep the abort listener through drain; start's finally removes it after failure.
    });
    try {
      const handle = await recording.ready;
      return {
        stop: async () => {
          try {
            return await handle.stop();
          } finally {
            recording.cleanup();
          }
        },
      };
    } catch (error) {
      recording.cleanup();
      throw error;
    }
  }
  async close() {
    this.closed = true;
    clearTimeout(this.timer);
    await this.buttons?.close();
    const active = this.active;
    if (active) {
      active.lost();
      await active.recording.cancel();
      active.recording.cleanup();
    }
    await this.refreshWork;
    await Promise.all([...this.probes.values()].map((probe) => probe.process.kill()));
    this.probes.clear();
    this.inputs = [];
  }
}
