const nativeZip = globalThis.__qjsp_native_zip;

export function open(...args) {
  if (!nativeZip || typeof nativeZip.open !== "function") {
    throw new Error("zip.open: native shim not installed");
  }
  return nativeZip.open(...args);
}

export function openFile(...args) {
  if (!nativeZip || typeof nativeZip.openFile !== "function") {
    throw new Error("zip.openFile: native shim not installed");
  }
  return nativeZip.openFile(...args);
}

export function create(...args) {
  if (!nativeZip || typeof nativeZip.create !== "function") {
    throw new Error("zip.create: native shim not installed");
  }
  return nativeZip.create(...args);
}

export function openPath(path) {
  return openFile(String(path));
}

export const ZipArchive = function () {
  throw new TypeError("ZipArchive is provided by native module; use open/openFile");
};