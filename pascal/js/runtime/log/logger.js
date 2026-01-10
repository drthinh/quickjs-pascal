import { levelToNumber, Levels } from "qjsp:log/levels.js";
import { consoleSink } from "qjsp:log/sinks.js";

let _defaultLevel = Levels.info;
let _defaultSink = consoleSink();
const _cache = new Map();

export function setDefaultLevel(level) {
  _defaultLevel = levelToNumber(level);
}

export function setDefaultSink(sink) {
  if (!sink || typeof sink.write !== "function") throw new TypeError("sink must have write(entry)");
  _defaultSink = sink;
}

export function getLogger(name) {
  name = String(name);
  const cached = _cache.get(name);
  if (cached) return cached;
  const logger = new Logger(name);
  _cache.set(name, logger);
  return logger;
}

export class Logger {
  constructor(name) {
    this.name = name;
    this.level = _defaultLevel;
    this.sink = _defaultSink;
  }

  setLevel(level) {
    this.level = levelToNumber(level);
    return this;
  }

  setSink(sink) {
    if (!sink || typeof sink.write !== "function") throw new TypeError("sink must have write(entry)");
    this.sink = sink;
    return this;
  }

  log(level, message, context) {
    const lvl = levelToNumber(level);
    if (lvl < this.level) return;
    this.sink.write({
      timeMs: Date.now(),
      level: lvl,
      name: this.name,
      message,
      context,
    });
  }

  trace(message, context) { this.log(Levels.trace, message, context); }
  debug(message, context) { this.log(Levels.debug, message, context); }
  info(message, context) { this.log(Levels.info, message, context); }
  warn(message, context) { this.log(Levels.warn, message, context); }
  error(message, context) { this.log(Levels.error, message, context); }
}
