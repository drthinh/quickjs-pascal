import * as fs from "qjsp:io/fs.js";
import { InputStream } from "qjsp:java/io/inputstream.js";
import { FileNotFoundException } from "qjsp:java/io/filenotfoundexception.js";

function _pathOf(p) {
  if (p && typeof p === "object" && typeof p.getPath === "function") return String(p.getPath());
  return String(p);
}

export class FileInputStream extends InputStream {
  constructor(file) {
    super();
    const path = _pathOf(file);
    try {
      this._buf = fs.readFile(path);
    } catch (e) {
      throw new FileNotFoundException(String(e && e.message ? e.message : e));
    }
    this._pos = 0;
    this._closed = false;
  }

  read() {
    if (this._closed) throw new Error("FileInputStream is closed");
    if (this._pos >= this._buf.length) return -1;
    return this._buf[this._pos++] & 0xff;
  }

  readBytes(b, off, len) {
    if (this._closed) throw new Error("FileInputStream is closed");
    return super.readBytes(b, off, len);
  }

  available() {
    if (this._closed) return 0;
    return this._buf.length - this._pos;
  }

  close() {
    this._closed = true;
  }
}

export default FileInputStream;
