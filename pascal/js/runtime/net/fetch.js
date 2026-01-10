import { toU8 } from "qjsp:util/bytes.js";
import { URL } from "qjsp:url/url.js";
import { acquirePump, releasePump } from "qjsp:runtime/pump.js";

function _normalizeHeaders(h) {
  if (h === void 0 || h === null) return void 0;
  if (Array.isArray(h)) return h;
  if (typeof h !== "object") throw new TypeError("net:fetch.fetch: headers must be object or array");
  return Object.entries(h);
}

function _headersObjectFromNative(h) {
  if (h === void 0 || h === null) return {};
  if (typeof h === "object") return h;
  return {};
}

export class Response {
  constructor(bodyU8, init) {
    this._body = bodyU8 || new Uint8Array(0);
    this.status = (init && init.status) | 0;
    this.ok = this.status >= 200 && this.status < 300;
    this.headers = _headersObjectFromNative(init && init.headers);
    this.url = init && init.url ? String(init.url) : "";
  }

  arrayBuffer() {
    const u8 = this._body;
    return Promise.resolve(u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength));
  }

  text() {
    return Promise.resolve(new TextDecoder().decode(this._body));
  }

  json() {
    return this.text().then((t) => JSON.parse(t));
  }
}

export function fetch(input, init) {
  const u = (input instanceof URL) ? input.toString() : String(input);
  const method = init && init.method ? String(init.method) : "GET";
  const headers = _normalizeHeaders(init && init.headers);
  const body = init && init.body;

  const nativeOpts = {
    timeoutMs: init && init.timeoutMs,
    followRedirects: init && init.followRedirects,
    responseType: "arraybuffer",
  };

  // Prefer real async primitive when available
  if (typeof globalThis.HttpRequestAsync === "function") {
    acquirePump("net:http", () => {
      if (typeof globalThis.PumpHttpRequests !== "function") return;
      try {
        globalThis.PumpHttpRequests();
      } catch (e) {
      }
    }, 10);

    return globalThis.HttpRequestAsync(method, u, headers, body, nativeOpts)
      .then(
        (r) => {
          const u8 = toU8(r.body);
          return new Response(u8, { status: r.status, headers: r.headers || {}, url: u });
        },
        (e) => {
          throw e;
        }
      )
      .then(
        (v) => {
          releasePump("net:http");
          return v;
        },
        (e) => {
          releasePump("net:http");
          throw e;
        }
      );
  }

  // Sync fallback
  if (typeof globalThis.HttpRequest !== "function") {
    return Promise.reject(new Error("net:fetch.fetch: HttpRequest/HttpRequestAsync is not available (http_helpers not registered)"));
  }

  const r = globalThis.HttpRequest(method, u, headers, body, nativeOpts);
  const u8 = toU8(r.body);
  const resp = new Response(u8, { status: r.status, headers: r.headers || {}, url: u });
  return Promise.resolve(resp);
}

export function installFetch() {
  if (globalThis.fetch === void 0) {
    globalThis.fetch = fetch;
  }
}
