import * as path from "qjsp:io/path.js";

export class Paths {
  static get(...parts) {
    return path.join(...parts);
  }

  static normalize(p) {
    return path.normalize(p);
  }

  static resolve(...parts) {
    return path.resolve(...parts);
  }

  static dirname(p) {
    return path.dirname(p);
  }

  static basename(p) {
    return path.basename(p);
  }

  static extname(p) {
    return path.extname(p);
  }

  static isAbsolute(p) {
    return path.isAbsolute(p);
  }
}
