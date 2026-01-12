import { OutputStream } from "qjsp:java/io/outputstream.js";

function _isOutputStreamLike(v) {
  return v != null &&
    typeof v.write === "function" &&
    typeof v.writeBytes === "function" &&
    typeof v.flush === "function" &&
    typeof v.close === "function";
}

function _str(x) {
  if (x === null) return "null";
  if (x === void 0) return "undefined";
  return String(x);
}

export class PrintStream {
  constructor(out, autoFlush) {
    if (!_isOutputStreamLike(out)) throw new TypeError("PrintStream(out[, autoFlush]): out must be OutputStream");
    this._out = out;
    this._autoFlush = !!autoFlush;
    this._closed = false;
    this._enc = new TextEncoder();
  }

  _writeString(s) {
    const u8 = this._enc.encode(String(s));
    this._out.writeBytes(u8);
  }

  write(b, off, len) {
    if (this._closed) throw new Error("PrintStream is closed");
    if (b instanceof Uint8Array) {
      this._out.writeBytes(b, off, len);
      return;
    }
    this._out.write(b);
  }

  print(x) {
    if (this._closed) throw new Error("PrintStream is closed");
    this._writeString(_str(x));
  }

  println(x) {
    if (this._closed) throw new Error("PrintStream is closed");
    if (arguments.length > 0) this._writeString(_str(x));
    this._writeString("\n");
    if (this._autoFlush) this.flush();
  }

  flush() {
    if (this._closed) return;
    this._out.flush();
  }

  close() {
    if (this._closed) return;
    this.flush();
    this._closed = true;
    this._out.close();
  }
}

export default PrintStream;
