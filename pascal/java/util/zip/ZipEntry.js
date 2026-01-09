export class ZipEntry {
  constructor(stat) {
    this._stat = stat && typeof stat === "object" ? stat : null;
  }

  getName() {
    return this._stat ? this._stat.name : null;
  }

  isDirectory() {
    return this._stat ? !!this._stat.isDirectory : false;
  }

  getCompressedSize() {
    return this._stat ? Number(this._stat.compressedSize) : 0;
  }

  getSize() {
    return this._stat ? Number(this._stat.uncompressedSize) : 0;
  }

  getCrc() {
    return this._stat ? Number(this._stat.crc32) : 0;
  }
}
