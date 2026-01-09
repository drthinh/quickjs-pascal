import { fetch } from "qjsp:net/fetch.js";

export class HttpResponse {
  constructor(uri, status, headers, body) {
    this._uri = uri;
    this._status = status | 0;
    this._headers = headers || {};
    this._body = body;
  }

  statusCode() {
    return this._status;
  }

  uri() {
    return this._uri;
  }

  headers() {
    return this._headers;
  }

  body() {
    return this._body;
  }
}

export const BodyHandlers = Object.freeze({
  ofString() {
    return async (resp) => await resp.text();
  },
  ofByteArray() {
    return async (resp) => {
      const ab = await resp.arrayBuffer();
      return new Uint8Array(ab);
    };
  },
});

export const BodyPublishers = Object.freeze({
  noBody() {
    return null;
  },
  ofString(text) {
    return String(text);
  },
  ofByteArray(bytes) {
    if (bytes instanceof Uint8Array) return bytes;
    if (bytes instanceof ArrayBuffer) return new Uint8Array(bytes);
    if (ArrayBuffer.isView(bytes)) return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    throw new TypeError("BodyPublishers.ofByteArray: expected Uint8Array/ArrayBuffer/view");
  },
});

class _HttpRequestBuilder {
  constructor(uri) {
    this._uri = uri;
    this._method = "GET";
    this._headers = [];
    this._body = null;
    this._timeoutMs = void 0;
    this._followRedirects = void 0;
  }

  uri(uri) {
    this._uri = uri;
    return this;
  }

  header(name, value) {
    this._headers.push([String(name), String(value)]);
    return this;
  }

  timeout(ms) {
    const n = Number(ms);
    if (!Number.isFinite(n) || n < 0) throw new RangeError("HttpRequest.Builder.timeout: ms must be >= 0");
    this._timeoutMs = n;
    return this;
  }

  followRedirects(v) {
    this._followRedirects = !!v;
    return this;
  }

  GET() {
    this._method = "GET";
    this._body = null;
    return this;
  }

  POST(bodyPublisher) {
    this._method = "POST";
    this._body = bodyPublisher;
    return this;
  }

  PUT(bodyPublisher) {
    this._method = "PUT";
    this._body = bodyPublisher;
    return this;
  }

  method(method, bodyPublisher) {
    this._method = String(method);
    this._body = bodyPublisher;
    return this;
  }

  build() {
    return new HttpRequest(this._uri, this._method, this._headers, this._body, {
      timeoutMs: this._timeoutMs,
      followRedirects: this._followRedirects,
    });
  }
}

export class HttpRequest {
  constructor(uri, method, headers, body, opts) {
    this._uri = uri;
    this._method = String(method || "GET");
    this._headers = Array.isArray(headers) ? headers : [];
    this._body = body;
    this._opts = opts && typeof opts === "object" ? opts : {};
  }

  static newBuilder(uri) {
    return new _HttpRequestBuilder(uri);
  }

  uri() {
    return this._uri;
  }

  method() {
    return this._method;
  }
}

export class HttpClient {
  static newHttpClient() {
    return new HttpClient();
  }

  sendAsync(request, bodyHandler) {
    if (!(request instanceof HttpRequest)) throw new TypeError("HttpClient.sendAsync: request must be HttpRequest");
    const handler = bodyHandler || BodyHandlers.ofByteArray();
    if (typeof handler !== "function") throw new TypeError("HttpClient.sendAsync: bodyHandler must be a function");

    const uri = request._uri;
    const url = uri && typeof uri.toString === "function" ? uri.toString() : String(uri);

    const headers = Array.isArray(request._headers) && request._headers.length > 0 ? request._headers : void 0;

    const init = {
      method: request._method,
      headers,
      body: request._body === void 0 ? null : request._body,
      timeoutMs: request._opts && request._opts.timeoutMs,
      followRedirects: request._opts && request._opts.followRedirects,
    };

    return fetch(url, init).then(async (resp) => {
      const body = await handler(resp);
      return new HttpResponse(uri, resp.status, resp.headers, body);
    });
  }
}
