const nativeSpawn = globalThis.__qjsp_native_spawn;

export function spawn(argv, opts) {
  if (!nativeSpawn || typeof nativeSpawn.spawn !== "function") {
    throw new Error("spawn: native shim not installed");
  }
  return nativeSpawn.spawn(argv, opts);
}

export function wait(id) {
  if (!nativeSpawn || typeof nativeSpawn.wait !== "function") {
    throw new Error("spawn.wait: native shim not installed");
  }
  return nativeSpawn.wait(id);
}

export function waitAsync(id) {
  if (!nativeSpawn || typeof nativeSpawn.waitAsync !== "function") {
    throw new Error("spawn.waitAsync: native shim not installed");
  }
  return nativeSpawn.waitAsync(id);
}

export function kill(id, sig) {
  if (!nativeSpawn || typeof nativeSpawn.kill !== "function") {
    throw new Error("spawn.kill: native shim not installed");
  }
  return nativeSpawn.kill(id, sig);
}
