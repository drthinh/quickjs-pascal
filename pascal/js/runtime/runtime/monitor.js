import { getPumpStats } from "qjsp:runtime/pump.js";

export function getRuntimeStats() {
  return {
    pump: getPumpStats(),
    watchCount: globalThis.__qjspWatchCount | 0,
    httpInflight: globalThis.__qjspHttpInflight | 0,
    debugLevel: globalThis.__qjspDebugLevel | 0,
  };
}
