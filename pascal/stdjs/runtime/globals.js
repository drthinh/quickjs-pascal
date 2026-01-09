import { installTextEncoding } from "qjsp:polyfills/text_encoding.js";
import * as os from "qjs:os";

export function installRuntimeGlobals() {
  installTextEncoding();

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
