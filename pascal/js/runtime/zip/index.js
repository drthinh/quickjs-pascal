import * as nativeZip from "qjsp:zip/native";

export const open = nativeZip.open;
export const openFile = nativeZip.openFile;
export const create = nativeZip.create;

export function openPath(path) {
  return openFile(String(path));
}

export const ZipArchive = function () {
  throw new TypeError("ZipArchive is provided by native module; use open/openFile");
};