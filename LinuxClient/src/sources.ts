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
  return unavailableReason(source, now) === null;
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

export function unavailableReason(source: Source | undefined, now = Date.now()): string | null {
  if (!source) return "Not currently reported by the server";
  const age = now - Date.parse(source.observedAt);
  if (!(age >= 0 && age <= 3500)) return "Status is out of date";
  if (!source.present) return "Disconnected";
  if (source.capture !== "available") return "Not ready to capture";
  if (source.link !== "connected" && source.link !== "notApplicable")
    return "Transmitter link is not ready";
  if (source.audioHealth === "degraded") return "Audio quality is degraded";
  return null;
}
export function selectionExplanation(
  sources: Source[],
  preferences: SourcePreferences,
  defaultID?: SourceID,
  now = Date.now(),
) {
  const next = candidates(sources, preferences, defaultID, now)[0] ?? null;
  if (!next)
    return {
      next,
      reason:
        "No eligible microphone is available for these settings. Availability is checked again at the next take.",
    };
  const fallback =
    defaultID && sourceKey(next.identity) === sourceKey(defaultID)
      ? "the system default microphone"
      : `an available microphone on ${preferences.hostID}`;
  if (preferences.mode === "fixed") {
    if (preferences.fixed && sourceKey(next.identity) === sourceKey(preferences.fixed))
      return {
        next,
        reason: "Using the fixed input. Host fallback remains available if capture cannot start.",
      };
    const fixed = sources.find(
      (source) => preferences.fixed && sourceKey(source.identity) === sourceKey(preferences.fixed),
    );
    return {
      next,
      reason: `Fixed input unavailable: ${unavailableReason(fixed, now)}. Using ${fallback}.`,
    };
  }
  if (preferences.mode === "systemDefault") {
    const explanation = !defaultID
      ? "The system default could not be identified. "
      : sourceKey(next.identity) !== sourceKey(defaultID)
        ? "The system default is unavailable. "
        : "";
    return { next, reason: `${explanation}Using ${fallback}.` };
  }
  const index = preferences.priority.findIndex((id) => sourceKey(id) === sourceKey(next.identity));
  if (index === 0)
    return { next, reason: "The first microphone in the selected priority list is ready." };
  if (index > 0)
    return {
      next,
      reason: `Using priority ${index + 1}; earlier microphones in the list are unavailable.`,
    };
  return {
    next,
    reason: `${preferences.priority.length ? "The listed microphones are unavailable" : "The priority list is empty"}. Using ${fallback}.`,
  };
}
