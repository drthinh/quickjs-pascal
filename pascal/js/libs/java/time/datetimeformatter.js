function _pad2(n) {
  return String(n).padStart(2, "0");
}

function _pad4(n) {
  return String(n).padStart(4, "0");
}

function _fmt(pattern, temporal) {
  let y, mo, d, h, mi, s;

  // Use duck-typing instead of instanceof because modules can be loaded via
  // different specifiers (e.g. qjsp:java/... vs relative), which breaks identity.
  if (temporal && typeof temporal === "object" &&
      typeof temporal.toLocalDate === "function" &&
      typeof temporal.toLocalTime === "function") {
    const dd = temporal.toLocalDate();
    const tt = temporal.toLocalTime();
    y = dd.getYear();
    mo = dd.getMonthValue();
    d = dd.getDayOfMonth();
    h = tt.getHour();
    mi = tt.getMinute();
    s = tt.getSecond();
  } else if (temporal && typeof temporal === "object" &&
      typeof temporal.getYear === "function" &&
      typeof temporal.getMonthValue === "function" &&
      typeof temporal.getDayOfMonth === "function") {
    y = temporal.getYear();
    mo = temporal.getMonthValue();
    d = temporal.getDayOfMonth();
    h = 0;
    mi = 0;
    s = 0;
  } else {
    throw new TypeError("DateTimeFormatter.format: unsupported temporal");
  }

  const p = String(pattern)
    .replace(/'([^']*)'/g, "$1");

  return p
    .replace(/yyyy/g, _pad4(y))
    .replace(/MM/g, _pad2(mo))
    .replace(/dd/g, _pad2(d))
    .replace(/HH/g, _pad2(h))
    .replace(/mm/g, _pad2(mi))
    .replace(/ss/g, _pad2(s));
}

export class DateTimeFormatter {
  constructor(pattern) {
    this._p = String(pattern);
  }

  static ofPattern(pattern) {
    return new DateTimeFormatter(pattern);
  }

  format(temporal) {
    return _fmt(this._p, temporal);
  }
}

DateTimeFormatter.ISO_LOCAL_DATE = DateTimeFormatter.ofPattern("yyyy-MM-dd");
DateTimeFormatter.ISO_LOCAL_DATE_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss");

export default DateTimeFormatter;
