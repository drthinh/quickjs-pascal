import { InputStream } from "qjsp:java/io/inputstream.js";
import { Reader } from "qjsp:java/io/reader.js";
import { InputStreamReader } from "qjsp:java/io/inputstreamreader.js";
import { BufferedReader } from "qjsp:java/io/bufferedreader.js";

function _isWhitespace(ch) {
  return ch === 32 || ch === 9 || ch === 10 || ch === 13 || ch === 12;
}

export class Scanner {
  constructor(source, charset) {
    if (source instanceof InputStream) {
      this._reader = new BufferedReader(new InputStreamReader(source, charset));
    } else if (source instanceof Reader) {
      this._reader = new BufferedReader(source);
    } else {
      throw new TypeError("Scanner(source): source must be InputStream or Reader");
    }

    this._buf = "";
    this._eof = false;
  }

  _ensure(n) {
    while (!this._eof && this._buf.length < n) {
      const line = this._reader.readLine();
      if (line === null) {
        this._eof = true;
        break;
      }
      this._buf += line + "\n";
    }
  }

  _skipDelims() {
    let i = 0;
    while (true) {
      this._ensure(i + 1);
      if (i >= this._buf.length) break;
      const ch = this._buf.charCodeAt(i);
      if (!_isWhitespace(ch)) break;
      i++;
    }
    if (i > 0) this._buf = this._buf.slice(i);
  }

  hasNext() {
    this._skipDelims();
    this._ensure(1);
    return this._buf.length > 0;
  }

  next() {
    this._skipDelims();
    this._ensure(1);
    if (this._buf.length === 0) throw new Error("NoSuchElement");

    let i = 0;
    while (true) {
      this._ensure(i + 1);
      if (i >= this._buf.length) break;
      const ch = this._buf.charCodeAt(i);
      if (_isWhitespace(ch)) break;
      i++;
    }

    const tok = this._buf.slice(0, i);
    this._buf = this._buf.slice(i);
    return tok;
  }

  nextLine() {
    this._ensure(1);
    if (this._buf.length === 0 && this._eof) throw new Error("NoSuchElement");

    const idx = this._buf.indexOf("\n");
    if (idx >= 0) {
      const line = this._buf.slice(0, idx);
      this._buf = this._buf.slice(idx + 1);
      return line.replace(/\r$/, "");
    }

    const line = this._buf;
    this._buf = "";
    return line.replace(/\r$/, "");
  }

  nextInt() {
    const s = this.next();
    const v = Number.parseInt(s, 10);
    if (!Number.isFinite(v)) throw new Error("InputMismatch");
    return v | 0;
  }

  nextDouble() {
    const s = this.next();
    const v = Number.parseFloat(s);
    if (!Number.isFinite(v)) throw new Error("InputMismatch");
    return v;
  }

  close() {
    this._reader.close();
  }
}

export default Scanner;
