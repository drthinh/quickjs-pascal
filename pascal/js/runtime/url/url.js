function _normalizeProtocol(p) {
  p = String(p || "");
  if (p === "") return "";
  if (!p.endsWith(":")) p += ":";
  return p;
}

function _parseUrl(input) {
  const s = String(input);
  const m = /^([A-Za-z][A-Za-z0-9+.-]*:)(\/\/)?(.*)$/.exec(s);
  if (!m) throw new TypeError("Invalid URL");

  const protocol = m[1];
  const hasSlashes = !!m[2];
  let rest = m[3] || "";

  let username = "";
  let password = "";
  let hostname = "";
  let port = "";
  let pathname = "";
  let search = "";
  let hash = "";

  if (!hasSlashes) {
    pathname = rest;
    return { protocol, username, password, hostname, port, pathname, search, hash };
  }

  const hashIdx = rest.indexOf("#");
  if (hashIdx >= 0) {
    hash = rest.slice(hashIdx);
    rest = rest.slice(0, hashIdx);
  }

  const searchIdx = rest.indexOf("?");
  if (searchIdx >= 0) {
    search = rest.slice(searchIdx);
    rest = rest.slice(0, searchIdx);
  }

  let authority = rest;
  let pathStart = rest.indexOf("/");
  if (pathStart >= 0) {
    authority = rest.slice(0, pathStart);
    pathname = rest.slice(pathStart) || "/";
  } else {
    pathname = "/";
  }

  const atIdx = authority.lastIndexOf("@");
  let hostPart = authority;
  if (atIdx >= 0) {
    const userinfo = authority.slice(0, atIdx);
    hostPart = authority.slice(atIdx + 1);
    const cIdx = userinfo.indexOf(":");
    if (cIdx >= 0) {
      username = userinfo.slice(0, cIdx);
      password = userinfo.slice(cIdx + 1);
    } else {
      username = userinfo;
    }
  }

  if (hostPart.startsWith("[")) {
    const end = hostPart.indexOf("]");
    if (end < 0) throw new TypeError("Invalid URL");
    hostname = hostPart.slice(0, end + 1);
    const after = hostPart.slice(end + 1);
    if (after.startsWith(":")) port = after.slice(1);
  } else {
    const pIdx = hostPart.lastIndexOf(":");
    if (pIdx >= 0 && hostPart.indexOf(":") === pIdx) {
      hostname = hostPart.slice(0, pIdx);
      port = hostPart.slice(pIdx + 1);
    } else {
      hostname = hostPart;
    }
  }

  return { protocol, username, password, hostname, port, pathname, search, hash };
}

function _resolveRelativeUrl(relative, base) {
  const rel = String(relative);
  const b = base;

  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(rel)) return rel;

  if (rel.startsWith("//")) {
    return b.protocol + rel;
  }

  if (rel.startsWith("#")) {
    return b.origin + b.pathname + b.search + rel;
  }

  if (rel.startsWith("?")) {
    return b.origin + b.pathname + rel;
  }

  if (rel.startsWith("/")) {
    return b.origin + rel;
  }

  const basePath = b.pathname || "/";
  const dir = basePath.endsWith("/") ? basePath : basePath.slice(0, basePath.lastIndexOf("/") + 1);
  return b.origin + dir + rel;
}

function _encodeQueryComponent(s) {
  return encodeURIComponent(String(s)).replace(/%20/g, "+");
}

function _decodeQueryComponent(s) {
  return decodeURIComponent(String(s).replace(/\+/g, "%20"));
}

export class URLSearchParams {
  constructor(init) {
    this._list = [];

    if (init === void 0 || init === null) return;

    if (typeof init === "string") {
      let s = init;
      if (s.startsWith("?")) s = s.slice(1);
      if (s === "") return;
      const parts = s.split("&");
      for (const part of parts) {
        if (part === "") continue;
        const eq = part.indexOf("=");
        if (eq < 0) {
          this.append(_decodeQueryComponent(part), "");
        } else {
          this.append(_decodeQueryComponent(part.slice(0, eq)), _decodeQueryComponent(part.slice(eq + 1)));
        }
      }
      return;
    }

    if (Array.isArray(init)) {
      for (const pair of init) {
        if (!Array.isArray(pair) || pair.length < 2) throw new TypeError("Invalid URLSearchParams init");
        this.append(pair[0], pair[1]);
      }
      return;
    }

    if (typeof init === "object") {
      for (const [k, v] of Object.entries(init)) {
        this.append(k, v);
      }
      return;
    }

    throw new TypeError("Invalid URLSearchParams init");
  }

  append(name, value) {
    this._list.push([String(name), String(value)]);
  }

  delete(name) {
    const n = String(name);
    this._list = this._list.filter((p) => p[0] !== n);
  }

  get(name) {
    const n = String(name);
    for (const p of this._list) {
      if (p[0] === n) return p[1];
    }
    return null;
  }

  getAll(name) {
    const n = String(name);
    const out = [];
    for (const p of this._list) {
      if (p[0] === n) out.push(p[1]);
    }
    return out;
  }

  has(name) {
    const n = String(name);
    return this._list.some((p) => p[0] === n);
  }

  set(name, value) {
    const n = String(name);
    const v = String(value);
    let found = false;
    const out = [];
    for (const p of this._list) {
      if (p[0] === n) {
        if (!found) {
          out.push([n, v]);
          found = true;
        }
      } else {
        out.push(p);
      }
    }
    if (!found) out.push([n, v]);
    this._list = out;
  }

  sort() {
    this._list.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  }

  forEach(callback, thisArg) {
    for (const [k, v] of this._list) {
      callback.call(thisArg, v, k, this);
    }
  }

  *keys() {
    for (const [k] of this._list) yield k;
  }

  *values() {
    for (const [, v] of this._list) yield v;
  }

  *entries() {
    for (const p of this._list) yield [p[0], p[1]];
  }

  [Symbol.iterator]() {
    return this.entries();
  }

  toString() {
    if (this._list.length === 0) return "";
    return this._list.map(([k, v]) => _encodeQueryComponent(k) + "=" + _encodeQueryComponent(v)).join("&");
  }
}

export class URL {
  constructor(input, base) {
    const inp = String(input);

    let full = inp;
    if (!/^[A-Za-z][A-Za-z0-9+.-]*:/.test(inp)) {
      if (base === void 0) throw new TypeError("Invalid URL");
      const b = base instanceof URL ? base : new URL(String(base));
      full = _resolveRelativeUrl(inp, b);
    }

    const parts = _parseUrl(full);

    this.protocol = _normalizeProtocol(parts.protocol);
    this.username = parts.username || "";
    this.password = parts.password || "";
    this.hostname = parts.hostname || "";
    this.port = parts.port || "";
    this.pathname = parts.pathname || "/";
    this.search = parts.search || "";
    this.hash = parts.hash || "";

    this.searchParams = new URLSearchParams(this.search);
  }

  get host() {
    return this.port ? this.hostname + ":" + this.port : this.hostname;
  }

  set host(v) {
    const s = String(v);
    const idx = s.lastIndexOf(":");
    if (idx >= 0 && s.indexOf(":") === idx) {
      this.hostname = s.slice(0, idx);
      this.port = s.slice(idx + 1);
    } else {
      this.hostname = s;
      this.port = "";
    }
  }

  get origin() {
    if (this.protocol === "") return "null";
    return this.protocol + "//" + this.host;
  }

  get href() {
    return this.toString();
  }

  set href(v) {
    const u = new URL(String(v));
    this.protocol = u.protocol;
    this.username = u.username;
    this.password = u.password;
    this.hostname = u.hostname;
    this.port = u.port;
    this.pathname = u.pathname;
    this.search = u.search;
    this.hash = u.hash;
    this.searchParams = new URLSearchParams(this.search);
  }

  toString() {
    const userinfo = this.username ? (this.username + (this.password ? ":" + this.password : "") + "@") : "";
    const query = this.searchParams.toString();
    const search = query ? "?" + query : (this.search && this.search !== "?" ? this.search : "");
    const hash = this.hash || "";
    return this.protocol + "//" + userinfo + this.host + (this.pathname || "/") + search + hash;
  }

  toJSON() {
    return this.toString();
  }
}
