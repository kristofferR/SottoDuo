import { createHash } from "node:crypto";
import { validateBody } from "../../../Server/src/validation.ts";
import { ClientNotice } from "./errors.ts";
import { sourceKey, type SourceID, type SourcePreferences } from "./sources.ts";

export interface MicrophoneProfile {
  id: string;
  name: string;
  priority: SourceID[];
}
export interface SavedInput {
  identity: SourceID;
  name: string;
}
export type ConfiguredSources = SourcePreferences & {
  server: string;
  profiles?: MicrophoneProfile[];
  activeProfileID?: string;
  knownInputs?: SavedInput[];
};
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function bounded(value: unknown, limit: number): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > limit)
    throw new ClientNotice(`Enter a name of 1–${limit} characters.`);
  return value.trim();
}
function identities(value: unknown): SourceID[] {
  if (!Array.isArray(value) || value.length > 32)
    throw new ClientNotice("A priority list can contain up to 32 microphones.");
  const result = value.map((id) => validateBody("AudioSourceIdentity", id));
  if (new Set(result.map(sourceKey)).size !== result.length)
    throw new ClientNotice("A microphone can appear only once in each priority list.");
  return result;
}
/** Legacy configs remain valid. Their current order becomes the first named list on save. */
export function profileFields(value: Record<string, unknown>) {
  if (
    value.profiles === undefined &&
    value.activeProfileID === undefined &&
    value.knownInputs === undefined
  )
    return {};
  if (!Array.isArray(value.profiles) || value.profiles.length < 1 || value.profiles.length > 16)
    throw new ClientNotice("Keep between 1 and 16 microphone priority lists.");
  const profiles = value.profiles.map((profile) => {
    if (!object(profile)) throw new ClientNotice("Invalid microphone priority list.");
    return {
      id: bounded(profile.id, 120),
      name: bounded(profile.name, 80),
      priority: identities(profile.priority),
    };
  });
  if (
    new Set(profiles.map((p) => p.id)).size !== profiles.length ||
    new Set(profiles.map((p) => p.name.toLowerCase())).size !== profiles.length
  )
    throw new ClientNotice("Each priority list needs a unique name and ID.");
  const active = profiles.find((p) => p.id === value.activeProfileID);
  if (!active) throw new ClientNotice("Choose an existing priority list.");
  if (
    JSON.stringify(active.priority.map(sourceKey)) !==
    JSON.stringify(identities(value.priority).map(sourceKey))
  )
    throw new ClientNotice("The selected priority list does not match the saved microphone order.");
  if (!Array.isArray(value.knownInputs) || value.knownInputs.length > 513)
    throw new ClientNotice("Invalid saved microphone names.");
  const referenced = new Set(profiles.flatMap((p) => p.priority.map(sourceKey)));
  if (value.fixed !== undefined)
    referenced.add(sourceKey(validateBody("AudioSourceIdentity", value.fixed)));
  const knownInputs = value.knownInputs
    .map((input) => {
      if (!object(input)) throw new ClientNotice("Invalid saved microphone name.");
      return {
        identity: validateBody("AudioSourceIdentity", input.identity),
        name: bounded(input.name, 200),
      };
    })
    .filter((input) => referenced.has(sourceKey(input.identity)));
  if (new Set(knownInputs.map((input) => sourceKey(input.identity))).size !== knownInputs.length)
    throw new ClientNotice("A saved microphone name can appear only once.");
  return { profiles, activeProfileID: active.id, knownInputs };
}
export function microphoneSettings(sources: ConfiguredSources) {
  return {
    ...sources,
    profiles: sources.profiles ?? [{ id: "default", name: "Default", priority: sources.priority }],
    activeProfileID: sources.activeProfileID ?? "default",
    knownInputs: sources.knownInputs ?? [],
  };
}
export function microphoneSnapshot(sources: ConfiguredSources) {
  const value = microphoneSettings(sources);
  return { value, revision: createHash("sha256").update(JSON.stringify(value)).digest("hex") };
}
/** Older clients edit the selected list, preserving every other saved list. */
export function legacySourceEdit(current: ConfiguredSources, value: unknown): unknown {
  if (!current.profiles || !object(value)) return value;
  return {
    ...value,
    profiles: current.profiles.map((profile) =>
      profile.id === current.activeProfileID ? { ...profile, priority: value.priority } : profile,
    ),
    activeProfileID: current.activeProfileID,
    knownInputs: current.knownInputs ?? [],
  };
}
