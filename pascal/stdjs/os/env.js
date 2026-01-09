import * as std from "qjs:std";

export function get(name, defaultValue) {
  const key = String(name);
  if (typeof std.getenv === "function") {
    const v = std.getenv(key);
    return v === null ? defaultValue : v;
  }
  return defaultValue;
}

export function set(name, value, overwrite) {
  const key = String(name);
  const val = String(value);
  const ow = overwrite === void 0 ? true : !!overwrite;
  if (typeof std.setenv === "function") {
    std.setenv(key, val, ow);
    return;
  }
  if (ow || get(key) === void 0) {
    if (typeof std.putenv === "function") {
      std.putenv(`${key}=${val}`);
      return;
    }
  }
  throw new Error("set: std.setenv/std.putenv not available");
}

export function unset(name) {
  const key = String(name);
  if (typeof std.unsetenv === "function") {
    std.unsetenv(key);
    return;
  }
  if (typeof std.putenv === "function") {
    std.putenv(`${key}=`);
    return;
  }
  throw new Error("unset: std.unsetenv/std.putenv not available");
}
