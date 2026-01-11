import { Duration as RtDuration } from "qjsp:time/duration.js";

export class Duration {
  constructor(ms) {
    this._d = new RtDuration(Number(ms));
  }

  static ofMillis(ms) {
    return new Duration(Number(ms));
  }

  static ofSeconds(sec) {
    return new Duration(Number(sec) * 1000);
  }

  static between(startInstant, endInstant) {
    const s = startInstant instanceof Object && typeof startInstant.valueOf === "function" ? Number(startInstant.valueOf()) : Number(startInstant);
    const e = endInstant instanceof Object && typeof endInstant.valueOf === "function" ? Number(endInstant.valueOf()) : Number(endInstant);
    return new Duration(e - s);
  }

  toMillis() {
    return this._d.toMillis();
  }

  toSeconds() {
    return this._d.toSeconds();
  }

  plus(other) {
    return new Duration(this._d.plus(other instanceof Duration ? other._d : other).toMillis());
  }

  minus(other) {
    return new Duration(this._d.minus(other instanceof Duration ? other._d : other).toMillis());
  }

  abs() {
    return new Duration(this._d.abs().toMillis());
  }

  valueOf() {
    return this._d.toMillis();
  }

  toString() {
    return this._d.toString();
  }
}

export default Duration;
