import { createHash } from "node:crypto";
import type { AudioStreamFormat } from "../api.ts";
import type { components } from "../generated/api.ts";

type Source = components["schemas"]["AudioSource"];
export interface PipeWireInput {
  source: Source;
  serial: string;
  format?: AudioStreamFormat;
  dji: boolean;
  card?: number;
}
const object = (value: unknown): Record<string, unknown> | undefined =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
const entries = (value: unknown) =>
  Array.isArray(value) ? value.map(object).filter((x) => x !== undefined) : [];
const nativeNumber = (value: unknown) =>
  typeof value === "number" ? value : object(value)?.default;

/** pw-dump reads graph metadata only; discovery never activates an audio stream. */
export function pipeWireInputs(value: unknown, hostID: string): PipeWireInput[] {
  if (!Array.isArray(value)) throw new Error("Invalid PipeWire graph.");
  const result: PipeWireInput[] = [];
  for (const item of entries(value)) {
    const info = object(item.info),
      props = object(info?.props),
      params = object(info?.params);
    if (item.type !== "PipeWire:Interface:Node" || props?.["media.class"] !== "Audio/Source")
      continue;
    const name = props["node.name"],
      serial = props["object.serial"];
    if (typeof name !== "string" || !Number.isSafeInteger(serial) || Number(serial) <= 0) continue;
    const device = entries(value).find(
      (d) => d.type === "PipeWire:Interface:Device" && d.id === props["device.id"],
    );
    const deviceProps = object(object(device?.info)?.props);
    const bluetoothDevice = deviceProps?.["device.api"] === "bluez5";
    if (props["api.bluez5.internal"] === true) continue;
    const bluetooth =
      bluetoothDevice || props["device.api"] === "bluez5" || name.startsWith("bluez_");
    const bluetoothInput =
      bluetoothDevice && (props["device.api"] === "bluez5" || props["bluez5.loopback"] === true);
    const connection = deviceProps?.["api.bluez5.connection"];
    const bluetoothLink =
      bluetoothDevice && (connection === "connected" || connection === "disconnected")
        ? connection
        : "unknown";
    const path = deviceProps?.["device.bus-path"];
    const id = createHash("sha256")
      .update(JSON.stringify([name, path ?? ""]))
      .digest("hex");
    const raw = entries(params?.EnumFormat).find(
      (f) => f.mediaType === "audio" && f.mediaSubtype === "raw",
    );
    // WirePlumber's headset auto-switch source advertises channels but no rate.
    // Request 48 kHz from that loopback; this is its delivered PCM, not the radio codec rate.
    const rate =
        bluetoothInput && props["bluez5.loopback"] === true && raw && raw.rate === undefined
          ? 48000
          : nativeNumber(raw?.rate),
      channels = nativeNumber(raw?.channels);
    const format =
      typeof rate === "number" &&
      Number.isInteger(rate) &&
      rate >= 8000 &&
      rate <= 192000 &&
      typeof channels === "number" &&
      Number.isInteger(channels) &&
      channels >= 1 &&
      channels <= 2
        ? { sampleRate: rate, channels }
        : undefined;
    const dji = props["alsa.components"] === "USB2ca3:4011";
    const muted = entries(params?.Props).some(
      (p) =>
        p.mute === true ||
        p.softMute === true ||
        (Array.isArray(p.channelVolumes) &&
          p.channelVolumes.length > 0 &&
          p.channelVolumes.every((v) => v === 0)),
    );
    const supported = (props["device.api"] === "alsa" || bluetoothInput) && !!format;
    const source: Source = {
      identity: { hostID, id },
      name: String(props["node.description"] || "PipeWire microphone").slice(0, 128),
      transport: bluetooth ? "bluetooth" : props["device.bus"] === "usb" ? "usb" : "builtIn",
      present: true,
      link: bluetooth ? bluetoothLink : dji ? "unknown" : "notApplicable",
      capture:
        !supported ||
        muted ||
        info?.state === "error" ||
        (bluetooth && bluetoothLink !== "connected")
          ? "unavailable"
          : dji
            ? "unknown"
            : "available",
      audioHealth: "unknown",
      observedAt: new Date().toISOString(),
      reason: muted
        ? "The PipeWire input is muted."
        : !supported
          ? "This provider supports ALSA and associated Bluetooth mono/stereo inputs with a usable capture format."
          : bluetooth && bluetoothLink !== "connected"
            ? "The Bluetooth microphone connection is not confirmed."
            : dji
              ? "Waiting for fresh DJI transmitter status; USB presence does not prove readiness."
              : undefined,
    };
    result.push({
      source,
      serial: String(serial),
      format,
      dji,
      card: typeof props["api.alsa.pcm.card"] === "number" ? props["api.alsa.pcm.card"] : undefined,
    });
  }
  // A generic serial or duplicated node name must never select an arbitrary device.
  const duplicates = new Set(
    result
      .filter(
        (x, i) => result.findIndex((y) => y.source.identity.id === x.source.identity.id) !== i,
      )
      .map((x) => x.source.identity.id),
  );
  return result.filter((x) => !duplicates.has(x.source.identity.id)).slice(0, 32);
}
