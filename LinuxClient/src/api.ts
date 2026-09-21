import { validateBody } from "../../Server/src/validation.ts";
import type { components } from "../../Server/src/generated/api.ts";
import type { SourceID } from "./sources.ts";
export type Generation = components["schemas"]["GenerationRecord"];
export type Device = components["schemas"]["DeviceIdentity"];
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
  async sources() {
    return validateBody("AudioSourceList", await this.request("/v1/audio-sources")).sources;
  }
  async start(
    requestID: string,
    device: Device,
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
        { requestID, device, mode: "dictation", source, buttonTicket },
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
  async delivery(id: string, owner: string, status: string) {
    await this.request(
      `/v1/generations/${id}/delivery`,
      "POST",
      { status, reportedAt: new Date().toISOString() },
      owner,
    );
  }
}
