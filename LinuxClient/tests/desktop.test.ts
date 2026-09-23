import { expect, test } from "bun:test";
import { desktopUnlocked } from "../src/desktop.ts";
const state = "LockedHint=no\nActive=yes\nType=wayland\nState=active\n";
const lock = {
  locked: false,
  requested: false,
  pending: false,
  sessionLocked: false,
  secure: false,
  lastEventAt: "",
};
const monitors = [{ solitaryBlockedBy: ["WINDOW"] }];
test("Omarchy lock checks reject pending, orphan and rapid lock/unlock even with stale logind hints", () => {
  expect(desktopUnlocked(state, lock, monitors, 1000)).toBe(true);
  for (const key of ["locked", "requested", "pending", "sessionLocked", "secure"])
    expect(desktopUnlocked(state, { ...lock, [key]: true }, monitors, 1000)).toBe(false);
  expect(desktopUnlocked(state, lock, [{ solitaryBlockedBy: ["LOCK"] }], 1000)).toBe(false);
  expect(desktopUnlocked(state, lock, [{ solitaryBlockedBy: ["WORKSPACE"] }], 1000)).toBe(false);
  expect(desktopUnlocked(state, lock, [{}], 1000)).toBe(false);
  expect(desktopUnlocked(state, lock, [], 1000)).toBe(false);
  expect(
    desktopUnlocked(state, { ...lock, lastEventAt: new Date(1001).toISOString() }, monitors, 1000),
  ).toBe(false);
  expect(desktopUnlocked(state.replace("Active=yes", "Active=no"), lock, monitors, 1000)).toBe(
    false,
  );
});

test("only exact namespaced compositor events control dictation", async () => {
  const { shortcutEvent } = await import("../src/desktop.ts");
  expect(["custom>>sottoduo:start", "custom>>sottoduo:stop"].map(shortcutEvent)).toEqual([
    "start",
    "stop",
  ]);
  for (const event of [
    "custom>>other:start",
    "custom>>sottoduo:start\nstop",
    "windowtitle>>sottoduo:start",
    "custom>>sottoduo:status",
  ])
    expect(shortcutEvent(event)).toBeUndefined();
});
