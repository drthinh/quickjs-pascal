import { toU8 } from "qjsp:util/bytes.js";
import { requireNative } from "qjsp:runtime/error.js";

function headersToPairs(headers) {
  if (headers === void 0 || headers === null) return void 0;
  if (Array.isArray(headers)) return headers;
  if (typeof headers !== "object") throw new TypeError("net:http.request: headers must be object or array");
  return Object.entries(headers);
}

function normalizeOptions(options) {
  if (options === void 0 || options === null) return void 0;
  if (typeof options !== "object") throw new TypeError("net:http.request: options must be object");
  return options;
}

export function request(method, url, ...args) {
  method = String(method || "GET");
  url = String(url);

  // Support both:
  // - request(method, url, options)
  // - request(method, url, headers, body, options)
  let options;
  if (args.length >= 3) {
    const headersArg = args[0];
    const bodyArg = args[1];
    const optionsArg = args[2];
    const o = normalizeOptions(optionsArg) || {};
    if (o.headers === void 0) o.headers = headersArg;
    if (o.body === void 0) o.body = bodyArg;
    options = o;
  } else {
    options = normalizeOptions(args[0]);
  }

  const headers = headersToPairs(options && options.headers);
  const body = options && options.body;

  // Global function injected by Pascal binding
  requireNative("net:http.request", globalThis, "HttpRequest");

  const respType = options && options.responseType;
  const nativeOpts = {
    timeoutMs: options && options.timeoutMs,
    followRedirects: options && options.followRedirects,
    responseType: respType,
    maxBytes: options && options.maxBytes,
  };

  const r = globalThis.HttpRequest(method, url, headers, body, nativeOpts);

  const bodyAb = r.body;
  const u8 = toU8(bodyAb);
  const res = {
    status: r.status,
    ok: r.status >= 200 && r.status < 300,
    url,
    headers: r.headers || {},
    body: u8,
    arrayBuffer: () => Promise.resolve(u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)),
    text: () => {
      if (r.bodyText !== void 0) return String(r.bodyText);
      return new TextDecoder().decode(u8);
    },
    json: () => JSON.parse((r.bodyText !== void 0) ? String(r.bodyText) : new TextDecoder().decode(u8)),
  };
  return res;
}

export function get(url, options) {
  return request("GET", url, options);
}

export function post(url, body, options) {
  options = options ? { ...options } : {};
  options.body = body;
  return request("POST", url, options);
}

export function getText(url, options) {
  options = options ? { ...options } : {};
  options.responseType = "text";
  const r = get(url, options);
  return r.text();
}

export function getJson(url, options) {
  options = options ? { ...options } : {};
  options.responseType = "text";
  const r = get(url, options);
  return r.json();
}

export function postJson(url, obj, options) {
  options = options ? { ...options } : {};
  const headers = { ...(options.headers || {}) };
  if (headers["content-type"] === void 0 && headers["Content-Type"] === void 0) {
    headers["content-type"] = "application/json";
  }
  options.headers = headers;
  options.responseType = "text";
  return post(url, JSON.stringify(obj), options);
}
