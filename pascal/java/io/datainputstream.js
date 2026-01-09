import { InputStream } from "qjsp:java/io/inputstream.js";
import { EOFException } from "qjsp:java/io/eofexception.js";

function _need(n) {
  throw new EOFException("unexpected end of stream");
}

export class DataInputStream {
  constructor(input) {
    if (!(input instanceof InputStream)) throw new TypeError("DataInputStream(input): input must be InputStream");
    this._in = input;
    this._tmp = new Uint8Array(8);
    this._dv = new DataView(this._tmp.buffer);
  }

  read() {
    return this._in.read();
  }

  readFully(b, off, len) {
    if (!(b instanceof Uint8Array)) throw new TypeError("DataInputStream.readFully: b must be Uint8Array");
    const o = off === void 0 ? 0 : (Number(off) | 0);
    const l = len === void 0 ? (b.length - o) : (Number(len) | 0);
    if (o < 0 || l < 0 || o > b.length || o + l > b.length) throw new RangeError("DataInputStream.readFully: invalid off/len");
    let got = 0;
    while (got < l) {
      const r = this._in.readBytes(b, o + got, l - got);
      if (r === -1) _need(l);
      got += r;
    }
  }

  _readN(n) {
    this.readFully(this._tmp, 0, n);
    return this._tmp;
  }

  readBoolean() {
    const v = this._in.read();
    if (v === -1) _need(1);
    return v !== 0;
  }

  readByte() {
    const v = this._in.read();
    if (v === -1) _need(1);
    return (v << 24) >> 24;
  }

  readUnsignedByte() {
    const v = this._in.read();
    if (v === -1) _need(1);
    return v & 0xff;
  }

  readShort() {
    this._readN(2);
    return this._dv.getInt16(0, false);
  }

  readUnsignedShort() {
    this._readN(2);
    return this._dv.getUint16(0, false);
  }

  readInt() {
    this._readN(4);
    return this._dv.getInt32(0, false);
  }

  readLong() {
    this._readN(8);
    const hi = BigInt(this._dv.getInt32(0, false));
    const lo = BigInt(this._dv.getUint32(4, false));
    return (hi << 32n) | lo;
  }

  readFloat() {
    this._readN(4);
    return this._dv.getFloat32(0, false);
  }

  readDouble() {
    this._readN(8);
    return this._dv.getFloat64(0, false);
  }

  close() {
    this._in.close();
  }
}

export default DataInputStream;
