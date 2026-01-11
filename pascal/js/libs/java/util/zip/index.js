import * as nativeZip from "qjsp:zip";

export { ZipEntry } from "qjsp:java/util/zip/ZipEntry.js";
export { ZipFile } from "qjsp:java/util/zip/ZipFile.js";

export const Zip = {
  create: nativeZip.create,
  open: nativeZip.open,
  openFile: nativeZip.openFile,
};
