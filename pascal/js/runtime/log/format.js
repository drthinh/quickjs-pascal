import { levelToName } from "qjsp:log/levels.js";

function _pad2(n) {
  n = String(n);
  return n.length === 1 ? "0" + n : n;
}

export function formatLine(entry) {
  const d = new Date(entry.timeMs);
  const ts =
    d.getFullYear() + "-" +
    _pad2(d.getMonth() + 1) + "-" +
    _pad2(d.getDate()) + " " +
    _pad2(d.getHours()) + ":" +
    _pad2(d.getMinutes()) + ":" +
    _pad2(d.getSeconds());

  const lvl = levelToName(entry.level);
  const name = entry.name ? String(entry.name) : "";
  const msg = entry.message ? String(entry.message) : "";
  const ctx = entry.context === void 0 ? "" : " " + safeJson(entry.context);

  return `${ts} ${lvl.toUpperCase()}${name ? " [" + name + "]" : ""} ${msg}${ctx}`;
}

export function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return "\"[unserializable]\"";
  }
}
