import { acquirePump, releasePump, shutdown as shutdownPumps } from "qjsp:runtime/pump.js";
export { acquirePump, releasePump };
export { selfCheckStdjs } from "qjsp:runtime/selfcheck.js";

export function shutdown() {
  const list = globalThis.__qjspRuntimeShutdownCallbacks;
  if (Array.isArray(list)) {
    for (let i = list.length - 1; i >= 0; i--) {
      const fn = list[i];
      if (typeof fn !== "function") continue;
      try {
        fn();
      } catch (e) {
      }
    }
    list.length = 0;
  }

  shutdownPumps();
}
