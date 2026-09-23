import { createHash, randomUUID } from "node:crypto";
import { lstat, mkdir, open, readFile, readdir, unlink } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { API, APIError } from "./api.ts";
import type { components } from "../../Server/src/generated/api.ts";
import { ClientNotice } from "./errors.ts";

const maximumAudioBytes = 128 * 1024 * 1024;
const retention = 15 * 60 * 1000;
const terminal = new Set(["completed", "failed", "cancelled"]);
type ArtifactName = components["schemas"]["WisprFlowArtifactName"];
const artifactNames = new Set<ArtifactName>([
  "source.json",
  "source.wav",
  "opus.json",
  "screenshot.png",
  "built-in-audio.bin",
]);
function artifactName(value: unknown): value is ArtifactName {
  return typeof value === "string" && artifactNames.has(value as ArtifactName);
}
function identifier(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value))
    throw new ClientNotice("Choose a valid history entry.");
  return value.toUpperCase();
}
function notice(error: unknown, operation: string): never {
  if (error instanceof ClientNotice) throw error;
  if (error instanceof APIError) {
    if ([401, 403].includes(error.status))
      throw new ClientNotice(
        "The server rejected the access token. Check Connection in This computer.",
      );
    if (error.status === 404)
      throw new ClientNotice("This entry or recording is no longer available. Refresh history.");
    if (error.status === 409)
      throw new ClientNotice("Finish or cancel this recording before deleting it.");
    if (error.status === 400)
      throw new ClientNotice("History changed. Refresh before loading older entries.");
  }
  throw new ClientNotice(
    `${operation} failed. Check the connection and refresh history before trying again.`,
  );
}
async function privateDirectory(path: string) {
  await mkdir(path, { mode: 0o700 }).catch((error) => {
    if (error.code !== "EEXIST") throw error;
  });
  const info = await lstat(path);
  if (!info.isDirectory() || info.uid !== process.getuid?.() || (info.mode & 0o077) !== 0)
    throw new ClientNotice(
      "The private audio folder is unavailable. Restart background dictation.",
    );
}
/** Only explicit history actions download or delete. No recording/delivery owner is involved. */
export class HistoryTools {
  private busy = false;
  private readonly scope: string;
  constructor(private readonly api: API) {
    this.scope = createHash("sha256").update(api.endpoint).digest("hex").slice(0, 24);
  }
  async list(before: unknown, source: unknown, queryID: unknown) {
    if (before !== undefined && (typeof before !== "string" || before.length > 512))
      throw new ClientNotice("Invalid history cursor. Refresh history.");
    if (source !== undefined && source !== "sotto" && source !== "wispr-flow")
      throw new ClientNotice("Choose Sotto, Wispr Flow or all sources.");
    if (queryID !== undefined && (typeof queryID !== "string" || queryID.length > 128))
      throw new ClientNotice("Invalid history request.");
    try {
      return { ...(await this.api.history(before, source)), server: this.api.endpoint, queryID };
    } catch (error) {
      return notice(error, "Loading history");
    }
  }
  async action(
    action: "deleteHistory" | "historyAudio" | "historyArtifact",
    request: Record<string, unknown>,
  ) {
    if (request.server !== this.api.endpoint)
      throw new ClientNotice("The connected server changed. Refresh history before continuing.");
    const id = identifier(request.id);
    if (this.busy) throw new ClientNotice("Wait for the current history action to finish.");
    this.busy = true;
    try {
      const record = await this.api.get(id, 60_000);
      if (action === "deleteHistory") {
        if (!terminal.has(record.status))
          throw new ClientNotice("Finish or cancel this recording before deleting it.");
        await this.api.deleteHistory(id);
        // Delete only cached copies for this server and entry. The server deletion is authoritative.
        await this.prune(`${this.scope}-${id}-`).catch(() => {});
        return { id, server: this.api.endpoint };
      }
      const kind = request.kind;
      const filename =
        action === "historyArtifact"
          ? artifactName(request.filename) &&
            record.importedSource?.artifactNames.includes(request.filename)
            ? request.filename
            : undefined
          : kind === "inference" && record.inferenceAudio
            ? "inference.wav"
            : kind === "original" && record.originalAudio
              ? "original.wav"
              : kind === "imported" && record.importedSource?.artifactNames.includes("source.wav")
                ? "source.wav"
                : undefined;
      if (!filename)
        throw new ClientNotice(
          action === "historyArtifact"
            ? "This entry has no saved source file of that kind."
            : "This entry has no saved recording of that kind.",
        );
      const directory = await this.directory();
      await this.prune();
      const path = join(
        directory,
        `${this.scope}-${id}-${randomUUID()}.${filename.split(".").at(-1)}`,
      );
      const file = await open(path, "wx+", 0o600);
      try {
        const response = await this.api.historyAudio(id, filename);
        if (!response.body) throw new Error("Empty audio response");
        const reader = response.body.getReader();
        try {
          const maximumBytes = filename.endsWith(".json") ? 8 * 1024 * 1024 : maximumAudioBytes;
          if (Number(response.headers.get("content-length")) > maximumBytes)
            throw new ClientNotice("This file is too large to open here.");
          let size = 0;
          for (;;) {
            const { value, done } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > maximumBytes) throw new ClientNotice("This file is too large to open here.");
            let offset = 0;
            while (offset < value.byteLength) {
              const { bytesWritten } = await file.write(value.subarray(offset));
              if (!bytesWritten) throw new Error("Could not write audio");
              offset += bytesWritten;
            }
          }
        } finally {
          await reader.cancel().catch(() => {});
          reader.releaseLock();
        }
        if (filename.endsWith(".wav")) {
          const header = Buffer.alloc(12);
          await file.read(header, 0, 12, 0);
          if (
            header.toString("ascii", 0, 4) !== "RIFF" ||
            header.toString("ascii", 8, 12) !== "WAVE"
          )
            throw new ClientNotice("The server did not return a playable WAV recording.");
        } else if (filename.endsWith(".png")) {
          const header = Buffer.alloc(8);
          await file.read(header, 0, 8, 0);
          if (!header.equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])))
            throw new ClientNotice("The server did not return a PNG screenshot.");
        } else if (filename.endsWith(".json")) {
          try {
            JSON.parse(await readFile(path, "utf8"));
          } catch {
            throw new ClientNotice("The server did not return a JSON source file.");
          }
        }
      } catch (error) {
        await unlink(path).catch(() => {});
        throw error;
      } finally {
        await file.close();
      }
      setTimeout(() => void unlink(path).catch(() => {}), retention).unref();
      return { id, kind, filename, server: this.api.endpoint, url: pathToFileURL(path).href };
    } catch (error) {
      return notice(
        error,
        action === "deleteHistory" ? "Deleting the entry" : "Opening the saved file",
      );
    } finally {
      this.busy = false;
    }
  }
  private async directory() {
    const runtime = process.env.XDG_RUNTIME_DIR;
    if (!runtime)
      throw new ClientNotice(
        "The desktop session is unavailable. Sign in again before opening audio.",
      );
    const base = join(runtime, "sotto-client");
    await privateDirectory(base);
    const directory = join(base, "history-audio");
    await privateDirectory(directory);
    return directory;
  }
  private async prune(prefix?: string) {
    const directory = await this.directory();
    const candidates = await Promise.all(
      (await readdir(directory))
        .filter((name) =>
          /^[a-f0-9]{24}-[A-F0-9-]{36}-[a-f0-9-]{36}\.(wav|json|png|bin)$/.test(name),
        )
        .map(async (name) => ({
          name,
          info: await lstat(join(directory, name)).catch(() => undefined),
        })),
    );
    const entries = candidates.flatMap((entry) =>
      entry.info ? [{ name: entry.name, info: entry.info }] : [],
    );
    entries.sort((a, b) => b.info.mtimeMs - a.info.mtimeMs);
    await Promise.all(
      entries
        .filter((entry, index) =>
          prefix
            ? entry.name.startsWith(prefix)
            : index >= 3 || Date.now() - entry.info.mtimeMs > retention,
        )
        .map((entry) =>
          unlink(join(directory, entry.name)).catch((error) => {
            if (error.code !== "ENOENT") throw error;
          }),
        ),
    );
  }
}
