import { requireNative } from "qjsp:runtime/error.js";

const nativeSpawn = globalThis.__qjsp_native_spawn;

export function spawn(argv, opts) {
  requireNative("spawn", nativeSpawn, "spawn");
  return nativeSpawn.spawn(argv, opts);
}

export function wait(id) {
  requireNative("spawn.wait", nativeSpawn, "wait");
  return nativeSpawn.wait(id);
}

export function waitAsync(id) {
  requireNative("spawn.waitAsync", nativeSpawn, "waitAsync");
  return nativeSpawn.waitAsync(id);
}

export function kill(id, sig) {
  requireNative("spawn.kill", nativeSpawn, "kill");
  return nativeSpawn.kill(id, sig);
}
