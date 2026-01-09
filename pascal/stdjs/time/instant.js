export class Instant {
  constructor(epochMs) {
    if (!Number.isFinite(epochMs)) throw new TypeError("Instant: epochMs must be a finite number");
    this.epochMs = epochMs;
    Object.freeze(this);
  }

  static now() {
    return new Instant(Date.now());
  }

  static fromEpochMs(ms) {
    return new Instant(Number(ms));
  }

  toDate() {
    return new Date(this.epochMs);
  }

  toISOString() {
    return new Date(this.epochMs).toISOString();
  }

  plus(duration) {
    return new Instant(this.epochMs + Number(duration.toMillis()));
  }

  minus(duration) {
    return new Instant(this.epochMs - Number(duration.toMillis()));
  }

  valueOf() {
    return this.epochMs;
  }

  toString() {
    return `Instant(${this.toISOString()})`;
  }
}
