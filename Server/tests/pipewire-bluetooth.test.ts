import { expect, test } from "bun:test";
import { pipeWireInputs } from "../src/capture/pipewire-discovery.ts";

// Sanitized WirePlumber graph observed with AirPods Pro 3, including its
// persistent auto-switch source while the device is still in A2DP playback mode.
function bluetoothGraph() {
  return [
    {
      id: 91,
      type: "PipeWire:Interface:Device",
      info: {
        props: {
          "device.api": "bluez5",
          "api.bluez5.connection": "connected",
          "bluez5.profile": "off",
        },
        params: { Profile: [{ name: "a2dp-sink-sbc_xq" }] },
      },
    },
    {
      id: 93,
      type: "PipeWire:Interface:Node",
      info: {
        state: "suspended",
        props: {
          "device.id": 91,
          "object.serial": 1044,
          "node.name": "bluez_input.00:11:22:33:44:55",
          "node.description": "Bluetooth headset",
          "media.class": "Audio/Source",
          "bluez5.loopback": true,
        },
        params: {
          EnumFormat: [{ mediaType: "audio", mediaSubtype: "raw", format: "F32P", channels: 1 }],
          Props: [{ mute: false }],
        },
      },
    },
  ];
}

function source(graph: unknown) {
  return pipeWireInputs(graph, "desktop")[0]!;
}

test("connected Bluetooth auto-switch source can negotiate PCM without a fixed advertised rate", () => {
  const input = source(bluetoothGraph());
  expect(input.format).toEqual({ sampleRate: 48000, channels: 1 });
  expect(input.source).toMatchObject({
    transport: "bluetooth",
    capture: "available",
    link: "connected",
    audioHealth: "unknown",
  });
  expect(input.dji).toBe(false);
});

test("Bluetooth admission requires a connected associated device, not just a source name", () => {
  const original = bluetoothGraph();
  const device = original[0]!;
  const node = original[1]!;
  for (const props of [
    { "device.api": "bluez5", "api.bluez5.connection": "disconnected" },
    { "device.api": "bluez5" },
    { "api.bluez5.connection": "connected" },
  ]) {
    const input = source([{ ...device, info: { ...device.info, props } }, node]);
    expect(input.source.capture).toBe("unavailable");
    expect(input.source.link).not.toBe("connected");
  }
  expect(source([node]).source.capture).toBe("unavailable");
  expect(source([{ ...device, type: "PipeWire:Interface:Node" }, node]).source.capture).toBe(
    "unavailable",
  );
});

test("Bluetooth identity survives profile switches and graph IDs changing; internal source is hidden", () => {
  const [device, node] = bluetoothGraph();
  const original = source([device, node]);
  const inputs = pipeWireInputs(
    [
      {
        ...device,
        id: 191,
        info: { ...device!.info, params: { Profile: [{ name: "headset-head-unit" }] } },
      },
      {
        ...node,
        id: 193,
        info: {
          ...node!.info,
          props: { ...node!.info.props, "device.id": 191, "object.serial": 2044 },
        },
      },
      {
        ...node,
        id: 194,
        info: {
          ...node!.info,
          props: {
            ...node!.info.props,
            "device.id": 191,
            "object.serial": 2045,
            "node.name": "bluez_input.00_11_22_33_44_55.0",
            "device.api": "bluez5",
            "api.bluez5.internal": true,
          },
        },
      },
    ],
    "desktop",
  );
  expect(inputs).toHaveLength(1);
  expect(inputs[0]!.source.identity).toEqual(original.source.identity);
  expect(inputs[0]!.serial).not.toBe(original.serial);
  expect(inputs[0]!.source.capture).toBe("available");
});

test("muted, broken and unsupported Bluetooth sources remain unavailable", () => {
  const [device, node] = bluetoothGraph();
  const info = node!.info;
  for (const change of [
    { state: "error" },
    { params: { ...info.params, Props: [{ mute: true }] } },
    { params: { ...info.params, Props: [{ softMute: true }] } },
    { params: { ...info.params, Props: [{ channelVolumes: [0] }] } },
    { params: { ...info.params, EnumFormat: [] } },
    {
      params: {
        ...info.params,
        EnumFormat: [{ mediaType: "audio", mediaSubtype: "raw", channels: 8 }],
      },
    },
    {
      params: {
        ...info.params,
        EnumFormat: [{ mediaType: "audio", mediaSubtype: "raw", channels: 1, rate: 0 }],
      },
    },
    { props: { ...info.props, "bluez5.loopback": false } },
  ]) {
    expect(source([device, { ...node, info: { ...info, ...change } }]).source.capture).toBe(
      "unavailable",
    );
  }
});

test("direct Bluetooth inputs use their reported rate and do not invent a missing format", () => {
  const [device, node] = bluetoothGraph();
  const info = node!.info;
  const direct = {
    ...node,
    info: { ...info, props: { ...info.props, "bluez5.loopback": false, "device.api": "bluez5" } },
  };
  expect(source([device, direct]).source.capture).toBe("unavailable");
  const input = source([
    device,
    {
      ...direct,
      info: {
        ...direct.info,
        params: {
          EnumFormat: [{ mediaType: "audio", mediaSubtype: "raw", rate: 16000, channels: 1 }],
        },
      },
    },
  ]);
  expect(input.format).toEqual({ sampleRate: 16000, channels: 1 });
  expect(input.source.capture).toBe("available");
});
