export class LocalTime {
  constructor(hour, minute, second, nano) {
    this._h = Number(hour) | 0;
    this._m = Number(minute) | 0;
    this._s = Number(second === void 0 ? 0 : second) | 0;
    this._n = Number(nano === void 0 ? 0 : nano) | 0;
  }

  static now() {
    const d = new Date();
    return new LocalTime(d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds() * 1000000);
  }

  static of(hour, minute, second, nano) {
    return new LocalTime(hour, minute, second, nano);
  }

  getHour() {
    return this._h;
  }

  getMinute() {
    return this._m;
  }

  getSecond() {
    return this._s;
  }

  getNano() {
    return this._n;
  }

  toString() {
    const hh = String(this._h).padStart(2, "0");
    const mm = String(this._m).padStart(2, "0");
    const ss = String(this._s).padStart(2, "0");
    return `${hh}:${mm}:${ss}`;
  }
}

export default LocalTime;
