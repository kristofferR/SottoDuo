import { validateBody } from "../../Server/src/validation.ts";
import type { components } from "../../Server/src/generated/api.ts";
import type { SourceID } from "./sources.ts";
export type Generation = components["schemas"]["GenerationRecord"];
export type Device = components["schemas"]["DeviceIdentity"];
export type CaptureMode = components["schemas"]["StartCaptureRequest"]["mode"];
export class APIError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(`Server request failed (${status}, ${code}).`);
  }
  get allowsFallback() {
    return (
      this.status === 503 &&
      ["source_unavailable", "capture_failed", "capture_timeout"].includes(this.code)
    );
  }
}
export class API {
  constructor(
    readonly endpoint: string,
    private token: string,
  ) {}
  async request(
    path: string,
    method = "GET",
    body?: unknown,
    owner?: string,
    timeout = 3000,
    destinationOwner?: string,
  ): Promise<unknown> {
    const response = await fetch(`${this.endpoint}${path}`, {
      method,
      redirect: "error",
      signal: AbortSignal.timeout(timeout),
      headers: {
        Authorization: `Bearer ${this.token}`,
        ...(destinationOwner ? { "X-Sotto-Destination-Owner": destinationOwner } : {}),
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        "X-Sotto-Capture": "capture-v1",
        "X-Sotto-Recognition": "streaming-v1",
        ...(owner ? { "X-Sotto-Capture-Owner": owner } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      let code = "http_error";
      try {
        code = validateBody("APIErrorResponse", await response.json()).code;
      } catch {
        /* Keep the bounded generic error. */
      }
      throw new APIError(response.status, code);
    }
    if (response.status === 204) return undefined;
    return response.json();
  }
  async buttonRequest(path: string, owner: string, body?: unknown, method = "POST") {
    return validateBody(
      "ButtonDestinationState",
      await this.request(`/v1/button-destinations${path}`, method, body, undefined, 1500, owner),
    );
  }
  async health() {
    return validateBody("ServerHealth", await this.request("/v1/health"));
  }
  async buttonStatus() {
    return validateBody("ButtonDestinationState", await this.request("/v1/button-destinations"));
  }
  async history(before?: string, source?: string) {
    return validateBody(
      "GenerationPage",
      await this.request(
        `/v1/generations?limit=30${before ? `&before=${encodeURIComponent(before)}` : ""}${source ? `&source=${encodeURIComponent(source)}` : ""}`,
        "GET",
        undefined,
        undefined,
        60_000,
      ),
    );
  }
  async deleteHistory(id: string) {
    await this.request(`/v1/generations/${encodeURIComponent(id)}`, "DELETE");
  }
  async historyAudio(
    id: string,
    filename: "inference.wav" | "original.wav" | components["schemas"]["WisprFlowArtifactName"],
  ) {
    const response = await fetch(
      `${this.endpoint}/v1/generations/${encodeURIComponent(id)}/artifacts/${filename}`,
      {
        redirect: "error",
        signal: AbortSignal.timeout(300_000),
        headers: { Authorization: `Bearer ${this.token}` },
      },
    );
    if (!response.ok) {
      await response.body?.cancel();
      throw new APIError(response.status, "audio_unavailable");
    }
    return response;
  }
  async preferences() {
    return validateBody(
      "PreferencesSnapshot",
      await this.request("/v1/preferences", "GET", undefined, undefined, 10_000),
    );
  }
  async savePreferences(value: unknown) {
    return validateBody(
      "PreferencesSnapshot",
      await this.request(
        "/v1/preferences",
        "PUT",
        validateBody("PreferencesSnapshot", value),
        undefined,
        10_000,
      ),
    );
  }
  async sources() {
    return validateBody("AudioSourceList", await this.request("/v1/audio-sources")).sources;
  }
  async start(
    requestID: string,
    device: Device,
    mode: CaptureMode,
    source: SourceID,
    owner: string,
    timeout: number,
    buttonTicket?: string,
  ) {
    return validateBody(
      "GenerationRecord",
      await this.request(
        "/v1/captures",
        "POST",
        { requestID, device, mode, source, buttonTicket },
        owner,
        timeout,
      ),
    );
  }
  async heartbeat(id: string, owner: string) {
    await this.request(`/v1/generations/${id}/capture/heartbeat`, "POST", undefined, owner, 1500);
  }
  async stop(id: string, owner: string) {
    return validateBody(
      "GenerationRecord",
      await this.request(`/v1/generations/${id}/capture/stop`, "POST", {}, owner, 5500),
    );
  }
  async cancel(id: string, owner: string) {
    await this.request(`/v1/generations/${id}/cancel`, "POST", {}, owner);
  }
  async get(id: string) {
    return validateBody("GenerationRecord", await this.request(`/v1/generations/${id}`));
  }
  async events(id: string, signal: AbortSignal, update: (record: Generation) => void) {
    const response = await fetch(`${this.endpoint}/v1/generations/${id}/events`, {
      redirect: "error",
      signal,
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: "application/x-ndjson",
        "X-Sotto-Capture": "capture-v1",
        "X-Sotto-Recognition": "streaming-v1",
      },
    });
    if (!response.ok || !response.body) {
      await response.body?.cancel();
      throw new Error("Live feedback is unavailable.");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder("utf-8", { fatal: true });
    let pending = "";
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) throw new Error("Live feedback disconnected.");
        pending += decoder.decode(value, { stream: true });
        let newline: number;
        while ((newline = pending.indexOf("\n")) >= 0) {
          if (newline > 2 * 1024 * 1024) throw new Error("Oversized feedback record.");
          const line = pending.slice(0, newline);
          pending = pending.slice(newline + 1);
          if (!line.trim()) continue;
          signal.throwIfAborted();
          const record = validateBody("GenerationRecord", JSON.parse(line));
          if (record.id !== id) throw new Error("Mismatched feedback record.");
          update(record);
          if (["completed", "failed", "cancelled"].includes(record.status)) return;
        }
        if (pending.length > 2 * 1024 * 1024) throw new Error("Oversized feedback record.");
      }
    } finally {
      await reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  }
  async delivery(id: string, owner: string, status: string) {
    await this.request(
      `/v1/generations/${id}/delivery`,
      "POST",
      { status, reportedAt: new Date().toISOString() },
      owner,
    );
  }
}
