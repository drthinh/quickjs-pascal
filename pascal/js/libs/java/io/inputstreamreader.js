import { InputStream } from "qjsp:java/io/inputstream.js";
import { Reader } from "qjsp:java/io/reader.js";

export class InputStreamReader extends Reader {
  constructor(input, charset) {
    super();
    if (!(input instanceof InputStream)) throw new TypeError("InputStreamReader(input[, charset]): input must be InputStream");
    this._in = input;
    this._dec = new TextDecoder(charset === void 0 ? "utf-8" : String(charset));
    this._buf = "";
    this._pos = 0;
    this._closed = false;
  }

  _fill() {
    const tmp = new Uint8Array(4096);
    const r = this._in.readBytes(tmp, 0, tmp.length);
    if (r === -1) return false;
    const chunk = tmp.subarray(0, r);
    this._buf = this._buf.slice(this._pos) + this._dec.decode(chunk, { stream: true });
    this._pos = 0;
    return this._buf.length > 0;
  }

  read() {
    if (this._closed) throw new Error("InputStreamReader is closed");
    if (this._pos >= this._buf.length) {
      if (!this._fill()) return -1;
    }
    const code = this._buf.charCodeAt(this._pos);
    this._pos++;
    return code;
  }

  close() {
    if (this._closed) return;
    this._closed = true;
    try {
      this._in.close();
    } catch (e) {
    }
  }
}

export default InputStreamReader;
