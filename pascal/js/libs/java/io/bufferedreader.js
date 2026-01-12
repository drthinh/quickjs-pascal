import { Reader } from "qjsp:java/io/reader.js";

export class BufferedReader extends Reader {
  constructor(reader, size) {
    super();
    if (!(reader instanceof Reader)) throw new TypeError("BufferedReader(reader[, size]): reader must be Reader");
    const n = size === void 0 ? 8192 : (Number(size) | 0);
    if (n <= 0) throw new RangeError("BufferedReader: size must be > 0");
    this._r = reader;
    this._closed = false;
    this._buf = "";
    this._pos = 0;
    this._max = n;
  }

  _fill() {
    if (this._pos < this._buf.length) return;
    const tmp = new Uint16Array(this._max);
    const n = this._r.readChars(tmp, 0, tmp.length);
    if (n === -1) {
      this._buf = "";
      this._pos = 0;
      return;
    }
    let s = "";
    for (let i = 0; i < n; i++) s += String.fromCharCode(tmp[i]);
    this._buf = s;
    this._pos = 0;
  }

  read() {
    if (this._closed) throw new Error("BufferedReader is closed");
    this._fill();
    if (this._pos >= this._buf.length) return -1;
    const c = this._buf.charCodeAt(this._pos);
    this._pos++;
    return c;
  }

  readLine() {
    if (this._closed) throw new Error("BufferedReader is closed");

    let out = "";
    while (true) {
      this._fill();
      if (this._pos >= this._buf.length) {
        return out.length === 0 ? null : out;
      }

      const ch = this._buf.charCodeAt(this._pos);
      this._pos++;

      if (ch === 10) {
        return out;
      }
      if (ch === 13) {
        this._fill();
        if (this._pos < this._buf.length && this._buf.charCodeAt(this._pos) === 10) this._pos++;
        return out;
      }

      out += String.fromCharCode(ch);
    }
  }

  close() {
    if (this._closed) return;
    this._closed = true;
    this._r.close();
  }
}

export default BufferedReader;
