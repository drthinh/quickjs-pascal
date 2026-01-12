export class LocalDate {
  constructor(year, month, day) {
    this._y = Number(year) | 0;
    this._m = Number(month) | 0;
    this._d = Number(day) | 0;
  }

  static now() {
    const d = new Date();
    return new LocalDate(d.getFullYear(), d.getMonth() + 1, d.getDate());
  }

  static of(year, month, day) {
    return new LocalDate(year, month, day);
  }

  getYear() {
    return this._y;
  }

  getMonthValue() {
    return this._m;
  }

  getDayOfMonth() {
    return this._d;
  }

  atTime(localTime) {
    const LocalDateTime = globalThis.__qjsp_java_time_LocalDateTime;
    if (typeof LocalDateTime !== "function") {
      throw new Error("LocalDate.atTime: LocalDateTime is not available (java/time/localdatetime.js not loaded)");
    }
    return LocalDateTime.of(this, localTime);
  }

  toString() {
    const y = String(this._y).padStart(4, "0");
    const m = String(this._m).padStart(2, "0");
    const d = String(this._d).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
}

export default LocalDate;
