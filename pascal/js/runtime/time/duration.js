export class Duration {
  constructor(ms) {
    if (!Number.isFinite(ms)) throw new TypeError("Duration: ms must be a finite number");
    this._ms = ms;
    Object.freeze(this);
  }

  static ofMillis(ms) {
    return new Duration(Number(ms));
  }

  static ofSeconds(sec) {
    return new Duration(Number(sec) * 1000);
  }

  static between(startInstant, endInstant) {
    return new Duration(Number(endInstant.valueOf()) - Number(startInstant.valueOf()));
  }

  toMillis() {
    return this._ms;
  }

  toSeconds() {
    return this._ms / 1000;
  }

  plus(other) {
    return new Duration(this._ms + Number(other.toMillis()));
  }

  minus(other) {
    return new Duration(this._ms - Number(other.toMillis()));
  }

  abs() {
    return new Duration(Math.abs(this._ms));
  }

  toString() {
    return `Duration(${this._ms}ms)`;
  }
}
