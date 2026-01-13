import { installTextEncoding } from "qjsp:polyfills/text_encoding.js";
import * as os from "qjs:os";
import { URL, URLSearchParams } from "qjsp:url/url.js";

function _installFetchLazy() {
  if (globalThis.fetch !== void 0) return;
  if (globalThis.__qjspFetchModulePromise === void 0) {
    globalThis.__qjspFetchModulePromise = null;
  }
  globalThis.fetch = function fetch(input, init) {
    if (globalThis.__qjspFetchModulePromise == null) {
      globalThis.__qjspFetchModulePromise = import("qjsp:net/fetch.js");
    }
    return globalThis.__qjspFetchModulePromise.then((m) => m.fetch(input, init));
  };
}

export function installRuntimeGlobals() {
  if (globalThis.__qjspRuntimeGlobalsInstalled) return;
  globalThis.__qjspRuntimeGlobalsInstalled = true;

  if (!Array.isArray(globalThis.__qjspRuntimeShutdownCallbacks)) {
    globalThis.__qjspRuntimeShutdownCallbacks = [];
  }

  installTextEncoding();

  if (globalThis.URL === void 0) globalThis.URL = URL;
  if (globalThis.URLSearchParams === void 0) globalThis.URLSearchParams = URLSearchParams;
  _installFetchLazy();

  if (globalThis.setTimeout === void 0 ||
      globalThis.clearTimeout === void 0 ||
      globalThis.setInterval === void 0 ||
      globalThis.clearInterval === void 0) {
    if (globalThis.setTimeout === void 0) globalThis.setTimeout = os.setTimeout;
    if (globalThis.clearTimeout === void 0) globalThis.clearTimeout = os.clearTimeout;
    if (globalThis.setInterval === void 0) globalThis.setInterval = os.setInterval;
    if (globalThis.clearInterval === void 0) globalThis.clearInterval = os.clearInterval;
  }

}

installRuntimeGlobals();

if ((globalThis.__qjspDebugLevel | 0) > 0) {
  try {
    const { selfCheckStdjs } = await import("qjsp:runtime/selfcheck.js");
    selfCheckStdjs({ root: "js/runtime" });
  } catch (e) {
    if (typeof globalThis.print === "function") {
      try {
        globalThis.print(String(e && e.stack ? e.stack : e));
      } catch (e2) {
      }
    }
    throw e;
  }
}
