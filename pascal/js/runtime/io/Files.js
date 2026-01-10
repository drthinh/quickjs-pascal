import * as fs from "qjsp:io/fs.js";

export class Files {
  static exists(p) {
    return fs.exists(p);
  }

  static readAllBytes(p) {
    return fs.readFile(p);
  }

  static readString(p) {
    return fs.readTextFile(p);
  }

  static write(p, data) {
    return fs.writeFile(p, data);
  }

  static writeString(p, text) {
    return fs.writeTextFile(p, text);
  }

  static createDirectories(p) {
    return fs.mkdirp(p);
  }

  static delete(p) {
    return fs.remove(p);
  }

  static move(from, to) {
    return fs.rename(from, to);
  }

  static list(p) {
    return fs.readdir(p);
  }
}
