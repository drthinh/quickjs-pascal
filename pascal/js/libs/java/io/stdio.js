import * as std from "qjs:std";

import { InputStream } from "qjsp:java/io/inputstream.js";
import { OutputStream } from "qjsp:java/io/outputstream.js";

export class StdinInputStream extends InputStream {
  constructor() {
    super();
    this._enc = new TextEncoder();
    this._buf = new Uint8Array(0);
    this._pos = 0;
    this._closed = false;
  }

  _fill() {
    if (this._closed) return false;
    if (!std || !std.in || typeof std.in.getline !== "function") return false;
    const line = std.in.getline();
    if (line == null) return false;
    const s = String(line);
    const u8 = this._enc.encode(s);
    const nl = this._enc.encode("\n");
    const out = new Uint8Array(u8.length + nl.length);
    out.set(u8, 0);
    out.set(nl, u8.length);
    this._buf = out;
    this._pos = 0;
    return true;
  }

  read() {
    if (this._closed) throw new Error("StdinInputStream is closed");
    if (this._pos >= this._buf.length) {
      if (!this._fill()) return -1;
    }
    return this._buf[this._pos++] & 0xff;
  }

  available() {
    if (this._closed) return 0;
    return this._buf.length - this._pos;
  }

  close() {
    this._closed = true;
  }
}

export class StdoutOutputStream extends OutputStream {
  constructor() {
    super();
    this._dec = new TextDecoder("utf-8");
    this._chunks = [];
    this._size = 0;
    this._closed = false;
  }

  _emit(s) {
    if (typeof std !== "undefined" && std && std.out && typeof std.out.puts === "function") {
      std.out.puts(String(s));
      return;
    }
    if (typeof std !== "undefined" && std && typeof std.print === "function") {
      std.print(String(s));
      return;
    }
  }

  write(b) {
    if (this._closed) throw new Error("StdoutOutputStream is closed");
    const v = Number(b);
    if (!Number.isFinite(v)) throw new TypeError("StdoutOutputStream.write: byte must be finite number");
    this._chunks.push(new Uint8Array([v & 0xff]));
    this._size += 1;
  }

  writeBytes(bytes, off, len) {
    if (this._closed) throw new Error("StdoutOutputStream is closed");
    if (!(bytes instanceof Uint8Array)) return super.writeBytes(bytes, off, len);

    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (bytes.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > bytes.length || o + l > bytes.length) throw new RangeError("StdoutOutputStream.writeBytes: invalid off/len");
    if (l === 0) return;
    const slice = bytes.subarray(o, o + l);
    const s = this._dec.decode(slice);
    this._emit(s);
  }

  flush() {
    if (this._closed) return;
    if (this._size === 0) return;

    let total = 0;
    for (const p of this._chunks) total += p.length;
    const out = new Uint8Array(total);
    let pos = 0;
    for (const p of this._chunks) {
      out.set(p, pos);
      pos += p.length;
    }

    this._chunks = [];
    this._size = 0;
    this._emit(this._dec.decode(out));
  }

  close() {
    if (this._closed) return;
    this.flush();
    this._closed = true;
  }
}

export class StderrOutputStream extends StdoutOutputStream {
  _emit(s) {
    if (typeof std !== "undefined" && std && std.err && typeof std.err.puts === "function") {
      std.err.puts(String(s));
      return;
    }
    return super._emit(s);
  }
}

export default {
  StdinInputStream,
  StdoutOutputStream,
  StderrOutputStream,
};
