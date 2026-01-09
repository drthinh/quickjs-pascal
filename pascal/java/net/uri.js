import { URL as QURL } from "qjsp:url/url.js";

function _hasScheme(s) {
  return /^[A-Za-z][A-Za-z0-9+.-]*:/.test(String(s));
}

export class URI {
  constructor(str) {
    this._raw = String(str);
    this._url = null;
    if (_hasScheme(this._raw)) {
      this._url = new QURL(this._raw);
    }
  }

  static create(str) {
    return new URI(str);
  }

  toString() {
    return this._raw;
  }

  getScheme() {
    if (!this._url) return null;
    const p = String(this._url.protocol || "");
    return p.endsWith(":") ? p.slice(0, -1) : p;
  }

  getHost() {
    if (!this._url) return null;
    return this._url.hostname || null;
  }

  getPort() {
    if (!this._url) return -1;
    const s = this._url.port || "";
    if (!s) return -1;
    const n = Number(s);
    return Number.isFinite(n) ? (n | 0) : -1;
  }

  getPath() {
    if (!this._url) return this._raw;
    return this._url.pathname || "";
  }

  getQuery() {
    if (!this._url) return null;
    const s = String(this._url.search || "");
    if (!s || s === "?") return null;
    return s.startsWith("?") ? s.slice(1) : s;
  }

  getFragment() {
    if (!this._url) return null;
    const s = String(this._url.hash || "");
    if (!s || s === "#") return null;
    return s.startsWith("#") ? s.slice(1) : s;
  }
}
