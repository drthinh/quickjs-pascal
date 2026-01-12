import { LocalDate } from "./localdate.js";
import { LocalTime } from "./localtime.js";

export class LocalDateTime {
  constructor(date, time) {
    this._d = date;
    this._t = time;
  }

  static now() {
    const d = new Date();
    const date = new LocalDate(d.getFullYear(), d.getMonth() + 1, d.getDate());
    const time = new LocalTime(d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds() * 1000000);
    return new LocalDateTime(date, time);
  }

  static of(a, b, c, d, e, f, g) {
    // Overloads:
    // - of(LocalDate, LocalTime)
    // - of(year, month, day, hour, minute[, second[, nano]])
    if (a && typeof a === "object" && typeof a.getYear === "function") {
      return new LocalDateTime(a, b);
    }
    const date = new LocalDate(a, b, c);
    const time = new LocalTime(d, e, f === void 0 ? 0 : f, g === void 0 ? 0 : g);
    return new LocalDateTime(date, time);
  }

  toLocalDate() {
    return this._d;
  }

  toLocalTime() {
    return this._t;
  }

  toString() {
    return `${this._d.toString()}T${this._t.toString()}`;
  }
}

globalThis.__qjsp_java_time_LocalDateTime = LocalDateTime;

export default LocalDateTime;
