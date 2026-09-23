import type { components } from "../../Server/src/generated/api.ts";
export type Source = components["schemas"]["AudioSource"];
export type SourceID = Source["identity"];
export interface SourcePreferences {
  hostID: string;
  mode: "automatic" | "systemDefault" | "fixed";
  priority: SourceID[];
  fixed?: SourceID;
}
export const sourceKey = (source: SourceID) => JSON.stringify([source.hostID, source.id]);
export function eligible(source: Source, now = Date.now()): boolean {
  const age = now - Date.parse(source.observedAt);
  return (
    age >= 0 &&
    age <= 3500 &&
    source.present &&
    source.capture === "available" &&
    (source.link === "connected" || source.link === "notApplicable") &&
    source.audioHealth !== "degraded"
  );
}
/** Same-host inputs are registered once by the server; never open a second local capture. */
export function candidates(
  sources: Source[],
  preferences: SourcePreferences,
  defaultID?: SourceID,
  now = Date.now(),
): Source[] {
  const available = sources.filter((source) => eligible(source, now));
  const local = available
    .filter((source) => source.identity.hostID === preferences.hostID)
    .sort((a, b) => sourceKey(a.identity).localeCompare(sourceKey(b.identity)));
  const fallback =
    local.find((source) => defaultID && sourceKey(source.identity) === sourceKey(defaultID)) ??
    local[0];
  const preferred =
    preferences.mode === "fixed"
      ? preferences.fixed
        ? [preferences.fixed]
        : []
      : preferences.mode === "automatic"
        ? preferences.priority
        : [];
  const ordered = preferred
    .map((id) => available.find((source) => sourceKey(source.identity) === sourceKey(id)))
    .filter((source) => source !== undefined);
  if (fallback) ordered.push(fallback);
  return ordered.filter(
    (source, index) =>
      ordered.findIndex((other) => sourceKey(other.identity) === sourceKey(source.identity)) ===
      index,
  );
}
