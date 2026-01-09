import { URL as QURL } from "qjsp:url/url.js";
import { URI } from "qjsp:java/net/uri.js";

export class URL {
  constructor(spec, context) {
    if (context !== void 0) {
      const base = context instanceof URL ? context.toString() : String(context);
      this._url = new QURL(String(spec), base);
    } else {
      this._url = new QURL(String(spec));
    }
  }

  toString() {
    return this._url.toString();
  }

  toURI() {
    return new URI(this.toString());
  }

  getProtocol() {
    const p = String(this._url.protocol || "");
    return p.endsWith(":") ? p.slice(0, -1) : p;
  }

  getHost() {
    return this._url.hostname || "";
  }

  getPort() {
    const s = this._url.port || "";
    if (!s) return -1;
    const n = Number(s);
    return Number.isFinite(n) ? (n | 0) : -1;
  }

  getPath() {
    return this._url.pathname || "";
  }

  getQuery() {
    const s = String(this._url.search || "");
    if (!s || s === "?") return null;
    return s.startsWith("?") ? s.slice(1) : s;
  }

  getRef() {
    const s = String(this._url.hash || "");
    if (!s || s === "#") return null;
    return s.startsWith("#") ? s.slice(1) : s;
  }
}
