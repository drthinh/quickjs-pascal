export const Levels = Object.freeze({
  trace: 10,
  debug: 20,
  info: 30,
  warn: 40,
  error: 50,
  off: 100,
});

export function levelToNumber(level) {
  if (typeof level === "number") return level;
  if (typeof level !== "string") throw new TypeError("level must be string|number");
  const k = level.toLowerCase();
  const v = Levels[k];
  if (v === void 0) throw new RangeError(`unknown log level: ${level}`);
  return v;
}

export function levelToName(levelNum) {
  const n = Number(levelNum);
  if (!Number.isFinite(n)) return "unknown";
  if (n <= Levels.trace) return "trace";
  if (n <= Levels.debug) return "debug";
  if (n <= Levels.info) return "info";
  if (n <= Levels.warn) return "warn";
  if (n <= Levels.error) return "error";
  return "off";
}
