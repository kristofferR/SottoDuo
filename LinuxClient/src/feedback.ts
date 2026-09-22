import type { Generation } from "./api.ts";
/** Display data only. Capture ownership and delivery stay with the controller. */
export class RecordingFeedback {
  private levels: number[] = [];
  private levelAt = -Infinity;
  private recordingAt?: number;
  private stoppedAt?: number;
  private stopAt?: number;
  private partialText = "";
  private streamAvailable: boolean | null = null;
  private limitReached = false;
  private processingStage?: Generation["status"];

  begin(stopAt: number, now = Date.now()) {
    this.recordingAt = now;
    this.stopAt = stopAt;
  }
  update(
    peak: number | undefined,
    partialText: string | undefined,
    stage: Generation["status"],
    now = Date.now(),
  ) {
    this.streamAvailable = true;
    this.partialText = partialText ?? "";
    this.processingStage = stage;
    if (this.stoppedAt !== undefined || peak === undefined || !Number.isFinite(peak)) return;
    this.levels = [...this.levels.slice(-8), Math.max(0, Math.min(1, peak))];
    this.levelAt = now;
  }
  unavailable() {
    this.streamAvailable = false;
    this.levels = [];
    this.partialText = "";
    this.processingStage = undefined;
  }
  finish(atLimit = false, now = Date.now()) {
    this.stoppedAt ??= now;
    this.limitReached = atLimit;
    this.levels = [];
  }
  snapshot(now = Date.now()) {
    const recording = this.recordingAt !== undefined && this.stoppedAt === undefined;
    return {
      levels: recording && this.streamAvailable && now - this.levelAt < 1500 ? this.levels : [],
      elapsedSeconds:
        this.recordingAt === undefined
          ? 0
          : Math.max(0, Math.floor(((this.stoppedAt ?? now) - this.recordingAt) / 1000)),
      remainingSeconds:
        recording && this.stopAt !== undefined
          ? Math.max(0, Math.ceil((this.stopAt - now) / 1000))
          : null,
      limitReached: this.limitReached,
      partialText: this.partialText,
      streamAvailable: this.streamAvailable,
      processingStage: this.processingStage,
    };
  }
}
