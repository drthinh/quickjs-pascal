import { Instant as RtInstant } from "qjsp:time/instant.js";
import { Duration } from "qjsp:java/time/duration.js";

export class Instant {
  constructor(epochMs) {
    this._i = new RtInstant(Number(epochMs));
  }

  static now() {
    return new Instant(RtInstant.now().valueOf());
  }

  static ofEpochMilli(ms) {
    return new Instant(Number(ms));
  }

  static fromEpochMs(ms) {
    return Instant.ofEpochMilli(ms);
  }

  toEpochMilli() {
    return Number(this._i.valueOf());
  }

  toDate() {
    return this._i.toDate();
  }

  toISOString() {
    return this._i.toISOString();
  }

  plus(duration) {
    return new Instant(this._i.plus(duration instanceof Duration ? duration._d : duration).valueOf());
  }

  minus(duration) {
    return new Instant(this._i.minus(duration instanceof Duration ? duration._d : duration).valueOf());
  }

  valueOf() {
    return this._i.valueOf();
  }

  toString() {
    return this._i.toString();
  }
}

export default Instant;
