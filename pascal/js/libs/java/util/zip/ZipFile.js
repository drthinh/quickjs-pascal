import * as nativeZip from "qjs:zip";
import { ZipEntry } from "qjsp:java/util/zip/ZipEntry.js";

export class ZipFile {
  constructor(archive) {
    this._zip = archive;
    this._closed = false;
  }

  static open(path) {
    return new ZipFile(nativeZip.openFile(String(path)));
  }

  static fromBytes(bytes) {
    if (bytes instanceof ArrayBuffer) return new ZipFile(nativeZip.open(bytes));
    if (bytes && bytes.buffer instanceof ArrayBuffer) return new ZipFile(nativeZip.open(bytes.buffer));
    throw new TypeError("ZipFile.fromBytes expects ArrayBuffer or Uint8Array");
  }

  close() {
    if (this._closed) return;
    this._zip.close();
    this._closed = true;
  }

  size() {
    return this._zip.numFiles();
  }

  entries() {
    const list = this._zip.list();
    return list.map((st) => new ZipEntry(st));
  }

  getEntry(name) {
    const st = this._zip.stat(String(name));
    return new ZipEntry(st);
  }

  getEntryBytes(nameOrIndex) {
    const ab = this._zip.read(nameOrIndex);
    return new Uint8Array(ab);
  }
}

export const Zip = {
  create: nativeZip.create,
  open: nativeZip.open,
  openFile: nativeZip.openFile,
};
