import { toU8 } from "qjsp:util/bytes.js";

function headersToPairs(headers) {
  if (headers === void 0 || headers === null) return void 0;
  if (Array.isArray(headers)) return headers;
  if (typeof headers !== "object") throw new TypeError("headers must be object or array");
  return Object.entries(headers);
}

function normalizeOptions(options) {
  if (options === void 0 || options === null) return void 0;
  if (typeof options !== "object") throw new TypeError("options must be object");
  return options;
}

export function request(method, url, options) {
  method = String(method || "GET");
  url = String(url);
  options = normalizeOptions(options);

  const headers = headersToPairs(options && options.headers);
  const body = options && options.body;

  // Global function injected by Pascal binding
  if (typeof globalThis.HttpRequest !== "function") {
    throw new Error("HttpRequest is not available (http_helpers not registered)");
  }

  const respType = options && options.responseType;
  const nativeOpts = {
    timeoutMs: options && options.timeoutMs,
    followRedirects: options && options.followRedirects,
    responseType: respType,
  };

  const r = globalThis.HttpRequest(method, url, headers, body, nativeOpts);

  const bodyAb = r.body;
  const u8 = toU8(bodyAb);
  const res = {
    status: r.status,
    headers: r.headers || {},
    body: u8,
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
