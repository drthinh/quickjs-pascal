import * as os from "qjs:os";
import * as env from "qjsp:os/env.js";
import * as sys from "qjsp:os/system.js";
import { PrintStream } from "qjsp:java/io/printstream.js";
import { StdinInputStream, StdoutOutputStream, StderrOutputStream } from "qjsp:java/io/stdio.js";

function _lineSeparator() {
  return sys.platform === "win32" ? "\r\n" : "\n";
}

function _getPropertyMap() {
  return {
    "line.separator": _lineSeparator(),
    "os.name": sys.platform,
    "os.arch": sys.arch,
    "user.home": sys.homedir(),
    "java.io.tmpdir": sys.tmpdir(),
  };
}

function _getProperty(key, defaultValue) {
  const k = String(key);
  const props = _getPropertyMap();
  if (Object.prototype.hasOwnProperty.call(props, k)) return props[k];

  // Common env-based fallbacks
  if (k === "user.name") {
    const v = env.get("USERNAME", env.get("USER", defaultValue));
    return v === void 0 ? defaultValue : v;
  }

  return defaultValue;
}

function _nanoTime() {
  if (typeof os.now === "function") {
    return BigInt(Math.floor(os.now() * 1000000));
  }
  return BigInt(Date.now()) * 1000000n;
}

export const System = Object.freeze({
  in: new StdinInputStream(),
  out: new PrintStream(new StdoutOutputStream(), true),
  err: new PrintStream(new StderrOutputStream(), true),
  currentTimeMillis() {
    return Date.now();
  },
  nanoTime() {
    return _nanoTime();
  },
  getProperty(key, defaultValue) {
    if (arguments.length === 0) throw new TypeError("System.getProperty(key[, defaultValue]): key is required");
    return _getProperty(key, defaultValue === void 0 ? null : defaultValue);
  },
  getProperties() {
    return Object.freeze({ ..._getPropertyMap() });
  },
  getenv(name) {
    if (arguments.length === 0) throw new TypeError("System.getenv(name): name is required");
    return env.get(String(name), null);
  },
  lineSeparator() {
    return _lineSeparator();
  },
});
