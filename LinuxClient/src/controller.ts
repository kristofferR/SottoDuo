import { randomBytes, randomUUID } from "node:crypto";
import { APIError, type API, type Device, type Generation } from "./api.ts";
import { candidates, sourceKey, type SourceID, type SourcePreferences } from "./sources.ts";
export interface Destination {
  deliver(text: string): Promise<"inserted" | "preview" | "uncertain">;
  close(): void;
}
export interface Desktop {
  unlocked(since?: number): Promise<boolean>;
  capture(): Promise<Destination>;
  defaultInput(hostID: string): Promise<SourceID | undefined>;
  notify(message: string): void;
}
type Take = {
  owner: string;
  requestID: string;
  id?: string;
  destination?: Destination;
  released: boolean;
  cancelled: boolean;
  startedAt: number;
  sealed: boolean;
  button?: { ticket: string; source: SourceID };
  completed?: boolean;
};
export interface Result {
  id: string;
  text: string;
  delivery: "inserted" | "preview" | "uncertain";
}
/** A process owns only its current take. Restart never reloads a generation for delivery. */
export class Controller {
  private take?: Take;
  private pending?: Promise<void>;
  private watchdog?: ReturnType<typeof setInterval>;
  private watching = false;
  private lastTick = Date.now();
  onStart?: (ticket?: string) => void;
  onComplete?: (id: string | undefined, ticket: string | undefined, succeeded: boolean) => void;
  state = "idle";
  result?: Result;
  constructor(
    private api: Pick<
      API,
      "sources" | "start" | "heartbeat" | "stop" | "cancel" | "get" | "delivery"
    >,
    private desktop: Desktop,
    private device: Device,
    private preferences: SourcePreferences,
  ) {}
  start(button?: Take["button"]): void {
    if (this.take) return;
    this.result = undefined;
    const take: Take = {
      owner: randomBytes(32).toString("hex"),
      requestID: randomUUID().toUpperCase(),
      released: false,
      cancelled: false,
      startedAt: Date.now(),
      sealed: false,
      button,
    };
    this.take = take;
    this.onStart?.(button?.ticket);
    this.lastTick = Date.now();
    this.setState("preparing");
    this.watchdog = setInterval(() => {
      void this.watch(take);
    }, 1000);
    this.pending = this.run(take)
      .catch(async () => {
        if (!take.cancelled)
          this.setState("Capture failed. Any completed result remains in shared history.");
        await this.cancelTake(take);
      })
      .finally(() => {
        take.destination?.close();
        if (this.take === take) {
          clearInterval(this.watchdog);
          this.take = undefined;
          this.onComplete?.(
            take.id,
            take.button?.ticket,
            take.completed === true && !take.cancelled,
          );
        }
      });
  }
  stop(): void {
    if (this.take && !this.take.button) this.take.released = true;
  }
  startButton(ticket: string, source: SourceID): boolean {
    if (this.take) return false;
    this.start({ ticket, source });
    return true;
  }
  stopButton(ticket: string): void {
    if (this.take?.button?.ticket === ticket) this.take.released = true;
  }
  async cancelButton(ticket?: string): Promise<void> {
    if (this.take?.button && (!ticket || this.take.button.ticket === ticket)) await this.cancel();
  }
  toggle(): void {
    if (this.take) this.stop();
    else this.start();
  }
  async cancel(): Promise<void> {
    const take = this.take;
    this.result = undefined;
    this.setState("cancelled");
    if (take) await this.cancelTake(take);
  }
  async settled(): Promise<void> {
    await this.pending;
  }
  private live(take: Take) {
    return this.take === take && !take.cancelled;
  }
  private setState(state: string) {
    this.state = state;
    this.desktop.notify(state);
  }
  private async cancelTake(take: Take) {
    take.cancelled = true;
    take.destination?.close();
    if (take.id && !take.sealed) await this.api.cancel(take.id, take.owner).catch(() => {});
    // An admission with an unknown ID loses its server lease within five seconds.
  }
  private async watch(take: Take) {
    if (this.watching || !this.live(take)) return;
    this.watching = true;
    try {
      const now = Date.now();
      const slept = now - this.lastTick > 2500 || now < this.lastTick;
      this.lastTick = now;
      const unlocked = await this.desktop.unlocked(take.startedAt);
      if (!this.live(take)) return;
      if (slept || !unlocked) {
        await this.cancel();
        return;
      }
      if (!take.released && now - take.startedAt >= 174000) take.released = true;
      if (take.id && !take.sealed && this.live(take)) {
        try {
          await this.api.heartbeat(take.id, take.owner);
        } catch (error) {
          if (
            !take.sealed &&
            !(
              take.released &&
              error instanceof APIError &&
              error.status === 409 &&
              error.code === "capture_closed"
            )
          )
            throw error;
        }
      }
    } catch {
      if (this.live(take)) {
        await this.cancelTake(take);
        this.setState("Connection lost; dictation cancelled.");
      }
    } finally {
      this.watching = false;
    }
  }
  private async run(take: Take) {
    // Establish the focus-change guard immediately, before slower lock/discovery checks.
    take.destination = await this.desktop.capture();
    if (!this.live(take)) return;
    if (!(await this.desktop.unlocked(take.startedAt)))
      throw new Error("Desktop is locked or unavailable.");
    const [sources, defaultID] = await Promise.all([
      this.api.sources(),
      this.desktop.defaultInput(this.preferences.hostID),
    ]);
    const options = take.button
      ? sources.filter((source) => sourceKey(source.identity) === sourceKey(take.button!.source))
      : candidates(sources, this.preferences, defaultID);
    for (const source of options.slice(0, 2)) {
      if (!this.live(take)) return;
      if (take.released) {
        this.setState("idle");
        return;
      }
      const remaining = 3000 - (Date.now() - take.startedAt);
      if (remaining <= 0) throw new Error("Activation timed out.");
      try {
        const record = await this.api.start(
          take.requestID,
          this.device,
          source.identity,
          take.owner,
          remaining,
          take.button?.ticket,
        );
        take.id = record.id;
        if (!this.live(take)) {
          await this.cancelTake(take);
          return;
        }
        if (
          record.capture?.state !== "recording" ||
          sourceKey(record.capture.source) !== sourceKey(source.identity) ||
          record.device.id !== this.device.id ||
          record.requestID !== take.requestID
        )
          throw new Error("Invalid capture admission.");
        this.setState(`recording · ${source.name}`);
        break;
      } catch (error) {
        if (take.button || !(error instanceof APIError && error.allowsFallback)) throw error;
        take.requestID = randomUUID().toUpperCase();
        take.owner = randomBytes(32).toString("hex");
      }
    }
    if (!take.id) throw new Error("No available microphone.");
    while (this.live(take) && !take.released) await Bun.sleep(40);
    if (!this.live(take)) return;
    this.setState("processing");
    let record = await this.api.stop(take.id, take.owner);
    this.verify(record, take);
    if (record.capture?.state !== "sealed") throw new Error("Capture was not sealed.");
    take.sealed = true;
    const deadline = Date.now() + 120000;
    while (this.live(take) && !["completed", "failed", "cancelled"].includes(record.status)) {
      if (Date.now() >= deadline) throw new Error("Processing timed out.");
      await Bun.sleep(300);
      if (!this.live(take)) return;
      record = await this.api.get(take.id);
    }
    if (!this.live(take)) return;
    this.verify(record, take);
    if (record.status !== "completed") throw new Error("Transcription did not complete.");
    if (!(await this.desktop.unlocked(take.startedAt)) || !this.live(take)) {
      await this.cancel();
      return;
    }
    // Exactly one attempt; an uncertain result is never retried or auto-copied.
    const delivery = await take.destination.deliver(record.insertionText);
    if (!this.live(take)) return;
    this.result = { id: take.id, text: record.insertionText, delivery };
    this.setState(
      delivery === "inserted"
        ? "Text inserted"
        : delivery === "uncertain"
          ? "Insertion uncertain. Check the field before copying."
          : "Text ready. Use sotto result or sotto copy.",
    );
    take.completed = Boolean(record.insertionText.trim()) && delivery !== "uncertain";
    await this.api
      .delivery(
        take.id,
        take.owner,
        delivery === "preview" ? "none" : delivery === "uncertain" ? "unconfirmed" : "inserted",
      )
      .catch(() => {
        this.desktop.notify("Delivery receipt could not be saved; insertion will not be retried.");
      });
  }
  private verify(record: Generation, take: Take) {
    if (
      record.id !== take.id ||
      record.requestID !== take.requestID ||
      record.device.id !== this.device.id
    )
      throw new Error("Mismatched generation.");
  }
}
