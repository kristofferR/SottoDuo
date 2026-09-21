import { randomBytes, randomUUID } from "node:crypto";
import type { API, Device } from "./api.ts";
import type { Controller, Desktop } from "./controller.ts";
import type { components } from "../../Server/src/generated/api.ts";
type State = components["schemas"]["ButtonDestinationState"];
type Registration = { id: string; owner: string; acknowledgement?: string };
/** Registration is consent for this process only; reconnecting never restores selection. */
export class ButtonDestinationClient {
  private registration?: Registration;
  private epoch = 0;
  private keyboardRegistration?: Registration;
  private closed = false;
  private pending?: Promise<void>;
  private lastTick = Date.now();
  state?: State;
  constructor(
    private api: Pick<API, "buttonRequest">,
    private desktop: Pick<Desktop, "unlocked">,
    private controller: Controller,
    private device: Device,
  ) {}
  start() {
    this.controller.onStart = (ticket) => {
      this.keyboardRegistration = ticket ? undefined : this.registration;
    };
    this.controller.onComplete = (id, ticket, succeeded) => {
      const registration = this.registration;
      if (!registration) return;
      if (ticket)
        void this.request(registration, "/complete", { takeID: ticket }).catch(() => {
          if (this.registration === registration) return this.disarm();
        });
      else if (succeeded && id && this.keyboardRegistration === registration)
        void this.select(id).catch(() => {});
    };
    this.pending ??= this.loop();
  }
  private async request(registration: Registration, path: string, body: unknown) {
    const state = await this.api.buttonRequest(
      `/${registration.id}${path}`,
      registration.owner,
      body,
    );
    if (this.registration === registration) this.state = state;
    return state;
  }
  async select(generationID?: string) {
    const registration = this.registration;
    if (!registration || !(await this.desktop.unlocked()) || this.registration !== registration)
      throw new Error("The button destination is not connected and unlocked.");
    return this.request(registration, "/select", generationID ? { generationID } : {});
  }
  async disarm() {
    ++this.epoch;
    const registration = this.registration;
    this.registration = undefined;
    this.keyboardRegistration = undefined;
    this.state = undefined;
    await this.controller.cancelButton();
    if (registration)
      await this.api
        .buttonRequest(`/${registration.id}`, registration.owner, undefined, "DELETE")
        .catch(() => {});
  }
  async close() {
    this.closed = true;
    this.controller.onComplete = undefined;
    this.controller.onStart = undefined;
    await this.disarm();
    await this.pending;
  }
  private async loop() {
    while (!this.closed) {
      try {
        await this.tick();
      } catch {
        await this.disarm();
      }
      if (!this.closed) await Bun.sleep(1000);
    }
  }
  async tick() {
    const epoch = this.epoch;
    const now = Date.now();
    const slept = now - this.lastTick > 3000 || now < this.lastTick;
    this.lastTick = now;
    if (slept || !(await this.desktop.unlocked())) {
      await this.disarm();
      return;
    }
    if (this.closed || epoch !== this.epoch) return;
    if (!this.registration) {
      const registration = {
        id: randomUUID().toUpperCase(),
        owner: randomBytes(32).toString("hex"),
      };
      const state = await this.api.buttonRequest("", registration.owner, {
        id: registration.id,
        device: this.device,
      });
      if (this.closed || epoch !== this.epoch) {
        await this.api
          .buttonRequest(`/${registration.id}`, registration.owner, undefined, "DELETE")
          .catch(() => {});
        return;
      }
      this.registration = registration;
      this.state = state;
    }
    const registration = this.registration;
    const state = await this.request(registration, "/heartbeat", {
      acknowledgement: registration.acknowledgement,
    });
    if (this.closed || epoch !== this.epoch || this.registration !== registration) return;
    const command = state.command;
    if (!command || command.id === registration.acknowledgement) return;
    registration.acknowledgement = command.id;
    if (Date.parse(command.expiresAt) <= Date.now()) {
      await this.disarm();
      return;
    }
    if (command.action === "cancel") await this.controller.cancelButton(command.takeID);
    else if (command.action === "stop") this.controller.stopButton(command.takeID);
    else {
      const unlocked = await this.desktop.unlocked();
      if (this.closed || epoch !== this.epoch || this.registration !== registration) return;
      if (!unlocked || Date.parse(command.expiresAt) <= Date.now()) {
        await this.disarm();
        return;
      }
      if (!this.controller.startButton(command.takeID, command.source))
        await this.request(registration, "/complete", { takeID: command.takeID });
    }
  }
}
