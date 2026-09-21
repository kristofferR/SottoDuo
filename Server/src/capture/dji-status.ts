// V2 only, validated against the Mini 2S captures in Ref #4. No command/write protocol.
export function djiCRC(bytes: Uint8Array, seed: number, polynomial: number) {
  let crc = seed;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? polynomial : 0);
  }
  return crc;
}

export class DJIStatus {
  private pending = Buffer.alloc(0);
  constructor(private readonly started = performance.now()) {}
  private lastFrameAt?: number;
  private observation?: { mask: number; at: number };

  push(bytes: Buffer, now = performance.now()) {
    if (bytes.length > 65_536) throw new Error("DJI status overflow.");
    this.pending = Buffer.concat([this.pending, bytes]);
    while (this.pending.length >= 4) {
      const length = this.pending[1]!;
      if (
        this.pending[0] !== 0x55 ||
        this.pending[2] !== 4 ||
        length < 14 ||
        djiCRC(this.pending.subarray(0, 3), 0x77, 0x8c) !== this.pending[3]
      ) {
        this.pending = this.pending.subarray(1);
        continue;
      }
      if (this.pending.length < length) break;
      const frame = this.pending.subarray(0, length);
      if (djiCRC(frame, 0x3692, 0x8408) !== 0) {
        this.pending = this.pending.subarray(1);
        continue;
      }
      this.pending = this.pending.subarray(length);
      if (
        frame.subarray(8, 12).toString("hex") !== "005b0303" ||
        ![54, 86, 118].includes(length) ||
        frame[12] !== length - 16 ||
        frame[13] !== 0 ||
        frame[44]! > 3
      )
        continue;
      // Discard the initial queued burst; require a later, naturally spaced full status.
      if (
        now - this.started >= 1_200 &&
        this.lastFrameAt !== undefined &&
        now - this.lastFrameAt >= 500 &&
        now - this.lastFrameAt < 2_500
      )
        this.observation = { mask: frame[44]!, at: now };
      else if (
        this.snapshot(now)?.mask !== frame[44] ||
        this.lastFrameAt === undefined ||
        now < this.lastFrameAt ||
        now - this.lastFrameAt >= 500
      )
        this.observation = undefined;
      // Rapid matching reports preserve established status without extending its lifetime.
      // A changed mask still invalidates immediately until a naturally spaced report arrives.
      this.lastFrameAt = now;
    }
  }
  snapshot(now = performance.now()) {
    return this.observation && now - this.observation.at < 2_500 ? this.observation : undefined;
  }
}
